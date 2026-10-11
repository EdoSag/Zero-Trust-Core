import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'account_backend.dart';

/// Result of any flow that leaves the vault unlocked.
class UnlockResult {
  const UnlockResult({required this.dek, this.newRecoveryKey});

  /// The user's data key. Hand it to the vault controller; never persist it
  /// outside secure storage.
  final Uint8List dek;

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
class AccountService {
  AccountService(
    this._backend, {
    this.params = KdfParams.current,
    this.legacyParams = KdfParams.current,
  });

  final AccountBackend _backend;
  final KdfParams params;

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
    await _store(keys.stored);
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
    final creds = await KeyHierarchy.deriveCredentials(
      password: password,
      salt: salt,
      params: params,
    );

    try {
      await _backend.signIn(email, creds.authSecret);
      final profile = await _requireProfile();
      if (!profile.isV2) throw const KeyMismatch();
      return UnlockResult(dek: await _unlock(password, profile));
    } on InvalidCredentials {
      // Fall through: maybe a pre-core account still using the raw password.
    }

    await _backend.signIn(email, password); // throws InvalidCredentials
    final profile = await _requireProfile();

    if (profile.isV2) {
      // An earlier upgrade stored v2 keys but failed before switching the
      // auth password. Finish it.
      final dek = await _unlock(password, profile);
      await _backend.updateAuthPassword(creds.authSecret);
      return UnlockResult(dek: dek);
    }

    final legacySalt = profile.legacySalt;
    if (legacySalt == null) throw const KeyMismatch();
    final keys = await KeyHierarchy.migrateLegacyAccount(
      password: password,
      legacySalt: legacySalt,
      salt: salt,
      legacyParams: legacyParams,
      params: params,
    );
    // Keys first, auth password second: if the second step fails, the next
    // sign-in lands in the isV2 branch above and completes it.
    await _store(keys.stored);
    await _backend.updateAuthPassword(keys.authSecret);
    return UnlockResult(dek: keys.dek, newRecoveryKey: keys.recoveryKey);
  }

  /// Re-derive the DEK for an already signed-in session (app relaunch).
  Future<Uint8List> unlock(String password) async =>
      _unlock(password, await _requireProfile());

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final profile = await _requireProfile();
    final dek = await _unlock(currentPassword, profile);
    await _setPassword(dek, newPassword, profile);
  }

  /// Forgot password. Call while holding the session from Supabase's
  /// password-reset email link; the recovery key proves the right to the
  /// data, the email link proves the right to the account.
  Future<UnlockResult> recover({
    required String recoveryKey,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final profile = await _requireProfile();
    if (!profile.isV2) throw const KeyMismatch();
    final dek = await KeyHierarchy.unlockWithRecoveryKey(
      recoveryKey: await RecoveryKey.parse(recoveryKey),
      stored: _wrapped(profile),
    );
    await _setPassword(dek, newPassword, profile);
    return UnlockResult(dek: dek);
  }

  /// Issue a new recovery key; the old one stops working.
  Future<RecoveryKey> rotateRecoveryKey(Uint8List dek) async {
    final rotated = await KeyHierarchy.rotateRecoveryKey(
      dek: dek,
      stored: _wrapped(await _requireProfile()),
    );
    await _store(rotated.stored);
    return rotated.recoveryKey;
  }

  Future<void> signOut() => _backend.signOut();

  Future<void> deleteAccount() => _backend.deleteAccount();

  Future<void> _setPassword(
    Uint8List dek,
    String newPassword,
    ProfileRecord profile,
  ) async {
    final email = _backend.currentEmail;
    if (email == null) throw StateError('Not signed in');
    final rewrapped = await KeyHierarchy.rewrapForNewPassword(
      dek: dek,
      newPassword: newPassword,
      stored: _wrapped(profile),
      salt: await Kdf.saltForEmail(email),
      params: params,
    );
    // Auth first: if storing the keys then fails, the old wrapping still
    // matches the old password for unlock, and the recovery key always works.
    await _backend.updateAuthPassword(rewrapped.authSecret);
    await _store(rewrapped.stored);
  }

  Future<Uint8List> _unlock(String password, ProfileRecord profile) async {
    if (!profile.isV2) throw const KeyMismatch();
    try {
      return await KeyHierarchy.unlockWithPassword(
        password: password,
        stored: _wrapped(profile),
      );
    } on Exception {
      throw const KeyMismatch();
    }
  }

  Future<ProfileRecord> _requireProfile() async {
    final profile = await _backend.fetchProfile();
    if (profile == null) throw const KeyMismatch();
    return profile;
  }

  WrappedKeys _wrapped(ProfileRecord p) => WrappedKeys(
        kdfSalt: p.kdfSalt!,
        kdfParams: KdfParams.fromJson(p.kdfParams!),
        wrappedDek: p.wrappedDek!,
        recoveryWrappedDek: p.recoveryWrappedDek!,
      );

  Future<void> _store(WrappedKeys k) => _backend.writeV2Keys(
        kdfSalt: k.kdfSalt,
        kdfParams: k.kdfParams.toJson(),
        wrappedDek: k.wrappedDek,
        recoveryWrappedDek: k.recoveryWrappedDek,
      );

  static void _checkPassword(String password) {
    if (password.length < 12) {
      throw ArgumentError('Password must be at least 12 characters.');
    }
  }
}
