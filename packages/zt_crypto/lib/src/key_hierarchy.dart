import 'dart:convert';
import 'dart:typed_data';

import 'kdf.dart';
import 'recovery_key.dart';
import 'sealed_box.dart';
import 'zt_base64.dart';

/// What the client derives from the password. Only [authSecret] is ever sent
/// to Supabase, as the Auth password; [kek] stays on the device.
class PasswordCredentials {
  const PasswordCredentials({required this.authSecret, required this.kek});

  /// Supabase Auth password. HKDF output, so the server cannot work back to
  /// the master key or the KEK.
  final String authSecret;

  /// Key-encryption key that wraps the user's DEK.
  final Uint8List kek;
}

/// The key material stored in `profiles` (v2). None of it is secret on its
/// own: the DEK inside is sealed under the KEK and under the recovery key.
class WrappedKeys {
  const WrappedKeys({
    required this.kdfSalt,
    required this.kdfParams,
    required this.wrappedDek,
    required this.recoveryWrappedDek,
  });

  final Uint8List kdfSalt;
  final KdfParams kdfParams;
  final Uint8List wrappedDek;
  final Uint8List recoveryWrappedDek;

  WrappedKeys copyWith({
    Uint8List? kdfSalt,
    KdfParams? kdfParams,
    Uint8List? wrappedDek,
    Uint8List? recoveryWrappedDek,
  }) =>
      WrappedKeys(
        kdfSalt: kdfSalt ?? this.kdfSalt,
        kdfParams: kdfParams ?? this.kdfParams,
        wrappedDek: wrappedDek ?? this.wrappedDek,
        recoveryWrappedDek: recoveryWrappedDek ?? this.recoveryWrappedDek,
      );
}

/// Result of creating or migrating an account: what to store, what to send
/// to Supabase Auth, what to keep in memory, and what to show the user once.
class NewAccountKeys {
  const NewAccountKeys({
    required this.stored,
    required this.authSecret,
    required this.dek,
    required this.recoveryKey,
  });

  final WrappedKeys stored;
  final String authSecret;
  final Uint8List dek;
  final RecoveryKey recoveryKey;
}

/// The Zero-Trust key hierarchy shared by every app:
///
/// ```
/// password -PBKDF2-> master key -HKDF("zt/auth/v1")-> authSecret (Supabase)
///                               -HKDF("zt/kek/v1")--> KEK
/// random DEK, sealed under KEK and under the recovery key
/// DEK -HKDF("zt/app/<id>/v1")-> per-app data key
/// ```
///
/// Changing the password re-wraps the DEK; no data is re-encrypted.
abstract final class KeyHierarchy {
  static const String _authInfo = 'zt/auth/v1';
  static const String _kekInfo = 'zt/kek/v1';
  static final List<int> _dekAad = utf8.encode('zt/dek/v1');
  static final List<int> _recoveryAad = utf8.encode('zt/dek-recovery/v1');

  static Future<PasswordCredentials> deriveCredentials({
    required String password,
    required List<int> salt,
    KdfParams params = KdfParams.current,
  }) async {
    final master =
        await Kdf.deriveMasterKey(password: password, salt: salt, params: params);
    try {
      return PasswordCredentials(
        authSecret: ZtBase64.encode(await Kdf.hkdf(master, _authInfo)),
        kek: await Kdf.hkdf(master, _kekInfo),
      );
    } finally {
      master.fillRange(0, master.length, 0);
    }
  }

  /// New user: fresh salt, fresh random DEK, fresh recovery key.
  /// New user: fresh random DEK and recovery key. [salt] is normally
  /// [Kdf.saltForEmail].
  static Future<NewAccountKeys> createAccount({
    required String password,
    required List<int> salt,
    KdfParams params = KdfParams.current,
  }) =>
      _wrapDek(
        dek: Kdf.randomBytes(Kdf.keyLength),
        password: password,
        salt: salt,
        params: params,
      );

  /// Existing (pre-core) user. Today's apps derive their data key directly as
  /// PBKDF2(password, profiles.salt), so adopting exactly that key as the DEK
  /// keeps every existing local database and cloud blob readable with no
  /// re-encryption. [legacySalt] may be in any base64 dialect.
  static Future<NewAccountKeys> migrateLegacyAccount({
    required String password,
    required String legacySalt,
    required List<int> salt,
    KdfParams legacyParams = KdfParams.current,
    KdfParams params = KdfParams.current,
  }) async {
    final legacyKey = await Kdf.deriveMasterKey(
      password: password,
      salt: ZtBase64.decode(legacySalt),
      params: legacyParams,
    );
    return _wrapDek(dek: legacyKey, password: password, salt: salt, params: params);
  }

  /// Unlock with the password. Throws `SecretBoxAuthenticationError` when the
  /// password is wrong.
  static Future<Uint8List> unlockWithPassword({
    required String password,
    required WrappedKeys stored,
  }) async {
    final creds = await deriveCredentials(
      password: password,
      salt: stored.kdfSalt,
      params: stored.kdfParams,
    );
    return SealedBox.open(stored.wrappedDek, creds.kek, aad: _dekAad);
  }

  static Future<Uint8List> unlockWithRecoveryKey({
    required RecoveryKey recoveryKey,
    required WrappedKeys stored,
  }) =>
      SealedBox.open(stored.recoveryWrappedDek, recoveryKey.bytes,
          aad: _recoveryAad);

  /// Change password (or set a new one after recovery). Same DEK, new KEK,
  /// new auth secret. The recovery wrapping is left unchanged. [salt] stays
  /// [Kdf.saltForEmail] unless the email itself changed.
  static Future<({WrappedKeys stored, String authSecret})> rewrapForNewPassword({
    required Uint8List dek,
    required String newPassword,
    required WrappedKeys stored,
    required List<int> salt,
    KdfParams params = KdfParams.current,
  }) async {
    final creds = await deriveCredentials(
      password: newPassword,
      salt: salt,
      params: params,
    );
    return (
      stored: stored.copyWith(
        kdfSalt: Uint8List.fromList(salt),
        kdfParams: params,
        wrappedDek: await SealedBox.seal(dek, creds.kek, aad: _dekAad),
      ),
      authSecret: creds.authSecret,
    );
  }

  /// Issue a new recovery key (for example when the old one was lost) and
  /// invalidate the previous one.
  static Future<({WrappedKeys stored, RecoveryKey recoveryKey})>
      rotateRecoveryKey({
    required Uint8List dek,
    required WrappedKeys stored,
  }) async {
    final recoveryKey = RecoveryKey.generate();
    return (
      stored: stored.copyWith(
        recoveryWrappedDek:
            await SealedBox.seal(dek, recoveryKey.bytes, aad: _recoveryAad),
      ),
      recoveryKey: recoveryKey,
    );
  }

  /// Per-app data key. Apps never use the DEK directly, so one app's data
  /// cannot be decrypted with a key handed to another app.
  static Future<Uint8List> appKey(Uint8List dek, String appId) {
    if (!RegExp(r'^[a-z_]+$').hasMatch(appId)) {
      throw ArgumentError.value(appId, 'appId', 'must match [a-z_]+');
    }
    return Kdf.hkdf(dek, 'zt/app/$appId/v1');
  }

  static Future<NewAccountKeys> _wrapDek({
    required Uint8List dek,
    required String password,
    required List<int> salt,
    required KdfParams params,
  }) async {
    final creds =
        await deriveCredentials(password: password, salt: salt, params: params);
    final recoveryKey = RecoveryKey.generate();
    return NewAccountKeys(
      stored: WrappedKeys(
        kdfSalt: Uint8List.fromList(salt),
        kdfParams: params,
        wrappedDek: await SealedBox.seal(dek, creds.kek, aad: _dekAad),
        recoveryWrappedDek:
            await SealedBox.seal(dek, recoveryKey.bytes, aad: _recoveryAad),
      ),
      authSecret: creds.authSecret,
      dek: dek,
      recoveryKey: recoveryKey,
    );
  }
}
