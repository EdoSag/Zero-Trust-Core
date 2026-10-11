import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'account_backend.dart';

/// Result of any flow that leaves the vault unlocked.
class UnlockResult {
  const UnlockResult({
    required this.dek,
    this.legacyDek = false,
    this.newRecoveryKey,
  });

  /// The user's data key. Hand it to the vault controller; never persist it
  /// outside secure storage.
  final Uint8List dek;

  /// The DEK is the pre-core key existing data was encrypted with directly.
  /// Pass this on to `VaultController.unlock` so apps can still read it.
  final bool legacyDek;

  /// Set after sign-up and after a legacy account is upgraded. The UI must
  /// show it once and make the user confirm they saved it.
  final RecoveryKey? newRecoveryKey;
}

/// Signed in, but the stored key material cannot be opened with this
/// password. Only the recovery key gets the user back in.
class KeyMismatch implements Exception {
  const KeyMismatch();
  @override
  String toString() => 'KeyMismatch';
}

/// One account across every Zero-Trust app. The password never leaves the
/// device: Supabase only sees an HKDF-derived auth secret.
///
/// Every multi-step change is ordered so an interruption at any point is
/// finished by the next sign-in or unlock, never a lock-out.
class AccountService {
  AccountService(
    this._backend, {
    this.params = KdfParams.current,
    this.previousParams = const [],
    this.legacyParams = KdfParams.current,
  });

  final AccountBackend _backend;

  /// KDF parameters for new keys and auth secrets.
  final KdfParams params;

  /// Parameters earlier releases used for the auth secret, newest first.
  /// The auth secret depends on them and they cannot be read before
  /// sign-in, so when [params] is raised the old set goes here: sign-in
  /// tries each, then moves the account to [params].
  final List<KdfParams> previousParams;

  /// How pre-core apps stretched the password (PBKDF2-SHA256, 600k).
  final KdfParams legacyParams;

  Future<UnlockResult> signUp({
    required String email,
    required String password,
  }) async {
    _checkPassword(password);
    final keys = await KeyHierarchy.createAccount(
      password: password,
      salt: await Kdf.saltForEmail(email),
      params: params,
    );
    await _backend.signUp(email, keys.authSecret);
    // If this write fails, the next sign-in sees an account with no keys
    // and finishes the sign-up (see _afterAuth).
    await _backend.writeKeys(_toStored(keys.stored));
    return UnlockResult(dek: keys.dek, newRecoveryKey: keys.recoveryKey);
  }

  /// Signs in and unlocks. Accounts made by pre-core app versions are
  /// upgraded on the way: their existing key becomes the DEK, so all local
  /// and cloud data stays readable.
  Future<UnlockResult> signIn({
    required String email,
    required String password,
  }) async {
    final salt = await Kdf.saltForEmail(email);
    for (final p in [params, ...previousParams]) {
      final creds = await KeyHierarchy.deriveCredentials(
          password: password, salt: salt, params: p);
      try {
        await _backend.signIn(email, creds.authSecret);
      } on InvalidCredentials {
        continue;
      }
      return _afterAuth(password, salt, authParams: p);
    }

    // Maybe a pre-core account still using the raw password.
    await _backend.signIn(email, password); // throws InvalidCredentials
    final profile = await _backend.fetchProfile();
    final creds = await KeyHierarchy.deriveCredentials(
        password: password, salt: salt, params: params);

    if (profile?.keys != null) {
      // An earlier upgrade stored v2 keys but failed before switching the
      // auth password. Finish it.
      final unlocked = await _unlock(password, profile!.keys!);
      await _backend.updateAuthPassword(creds.authSecret);
      return unlocked;
    }

    final legacySalt = profile?.legacySalt;
    if (legacySalt == null) throw const KeyMismatch();
    final keys = await KeyHierarchy.migrateLegacyAccount(
      password: password,
      legacySalt: legacySalt,
      salt: salt,
      legacyParams: legacyParams,
      params: params,
    );
    // Keys first, auth password second: if the second step fails, the next
    // sign-in lands in the branch above and completes it.
    await _backend.writeKeys(_toStored(keys.stored, legacyDek: true));
    await _backend.updateAuthPassword(keys.authSecret);
    return UnlockResult(
      dek: keys.dek,
      legacyDek: true,
      newRecoveryKey: keys.recoveryKey,
    );
  }

  /// Re-derive the DEK for an already signed-in session (app relaunch).
  Future<UnlockResult> unlock(String password) async {
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys == null) throw const KeyMismatch();
    return _unlock(password, keys);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys == null) throw const KeyMismatch();
    final unlocked = await _unlock(currentPassword, keys);
    await _setPassword(unlocked.dek, newPassword);
  }

  /// Forgot password. Call while holding the session from Supabase's
  /// password-reset email link; the recovery key proves the right to the
  /// data, the email link proves the right to the account.
  Future<UnlockResult> recover({
    required String recoveryKey,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys == null) throw const KeyMismatch();
    final dek = await KeyHierarchy.unlockWithRecoveryKey(
      recoveryKey: await RecoveryKey.parse(recoveryKey),
      stored: _wrapped(keys),
    );
    await _setPassword(dek, newPassword);
    return UnlockResult(dek: dek, legacyDek: keys.legacyDek);
  }

  /// Issue a new recovery key; the old one stops working.
  Future<RecoveryKey> rotateRecoveryKey(Uint8List dek) async {
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys == null) throw const KeyMismatch();
    final rotated =
        await KeyHierarchy.rotateRecoveryKey(dek: dek, stored: _wrapped(keys));
    await _backend.writeKeys(
        keys.copyWith(recoveryWrappedDek: rotated.stored.recoveryWrappedDek));
    return rotated.recoveryKey;
  }

  Future<void> signOut() => _backend.signOut();

  Future<void> deleteAccount() => _backend.deleteAccount();

  Future<UnlockResult> _afterAuth(
    String password,
    Uint8List salt, {
    required KdfParams authParams,
  }) async {
    final profile = await _backend.fetchProfile();
    final keys = profile?.keys;

    if (keys == null) {
      if (profile?.legacySalt != null) throw const KeyMismatch();
      // Sign-up created the auth user but never stored keys. No data can
      // exist yet, so finish it with fresh keys; the auth secret is the one
      // just used, because it depends only on password, email and params.
      final created = await KeyHierarchy.createAccount(
          password: password, salt: salt, params: authParams);
      await _backend.writeKeys(_toStored(created.stored));
      if (authParams != params) await _setPassword(created.dek, password);
      return UnlockResult(dek: created.dek, newRecoveryKey: created.recoveryKey);
    }

    final unlocked = await _unlock(password, keys);
    if (authParams != params) {
      // Signed in with an older KDF setting: move the account forward.
      await _setPassword(unlocked.dek, password);
    }
    return unlocked;
  }

  /// Three writes, each safe to interrupt:
  /// 1. store the new wrapping as *pending* (old password still works),
  /// 2. switch the auth password,
  /// 3. promote pending to current.
  /// After 2 without 3, [_unlock] finds the pending wrapping and promotes it.
  Future<void> _setPassword(Uint8List dek, String newPassword) async {
    final email = _backend.currentEmail;
    if (email == null) throw StateError('Not signed in');
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys == null) throw const KeyMismatch();
    final rewrapped = await KeyHierarchy.rewrapForNewPassword(
      dek: dek,
      newPassword: newPassword,
      stored: _wrapped(keys),
      salt: await Kdf.saltForEmail(email),
      params: params,
    );
    final pending = keys.copyWith(
      pendingWrappedDek: rewrapped.stored.wrappedDek,
      pendingKdfParams: params.toJson(),
    );
    await _backend.writeKeys(pending);
    await _backend.updateAuthPassword(rewrapped.authSecret);
    await _backend.writeKeys(_promote(pending));
  }

  Future<UnlockResult> _unlock(String password, StoredKeys keys) async {
    try {
      final dek = await KeyHierarchy.unlockWithPassword(
          password: password, stored: _wrapped(keys));
      return UnlockResult(dek: dek, legacyDek: keys.legacyDek);
    } on Exception {
      // Fall through to a pending wrapping from an interrupted change.
    }
    final pending = keys.pendingWrappedDek;
    if (pending == null) throw const KeyMismatch();
    try {
      final promoted = _promote(keys);
      final dek = await KeyHierarchy.unlockWithPassword(
          password: password, stored: _wrapped(promoted));
      await _backend.writeKeys(promoted);
      return UnlockResult(dek: dek, legacyDek: keys.legacyDek);
    } on Exception {
      throw const KeyMismatch();
    }
  }

  static StoredKeys _promote(StoredKeys k) => k.copyWith(
        wrappedDek: k.pendingWrappedDek,
        kdfParams: k.pendingKdfParams,
        clearPending: true,
      );

  static WrappedKeys _wrapped(StoredKeys k) => WrappedKeys(
        kdfSalt: k.kdfSalt,
        kdfParams: KdfParams.fromJson(k.kdfParams),
        wrappedDek: k.wrappedDek,
        recoveryWrappedDek: k.recoveryWrappedDek,
      );

  static StoredKeys _toStored(WrappedKeys k, {bool legacyDek = false}) =>
      StoredKeys(
        kdfSalt: k.kdfSalt,
        kdfParams: k.kdfParams.toJson(),
        wrappedDek: k.wrappedDek,
        recoveryWrappedDek: k.recoveryWrappedDek,
        legacyDek: legacyDek,
      );

  static void _checkPassword(String password) {
    if (password.length < 12) {
      throw ArgumentError('Password must be at least 12 characters.');
    }
  }
}
