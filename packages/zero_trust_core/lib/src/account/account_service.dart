import 'dart:async';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'account_backend.dart';
import 'biometric_key_store.dart';
import 'key_cache.dart';

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
    KeyCache? keyCache,
    BiometricKeyStore? biometrics,
    this.onlineTimeout = const Duration(seconds: 8),
  })  : _cache = keyCache ?? InMemoryKeyCache(),
        _biometrics = biometrics;

  final AccountBackend _backend;
  final KeyCache _cache;
  final BiometricKeyStore? _biometrics;

  /// How long [unlock] waits for the server before using the device's copy
  /// of the keys.
  final Duration onlineTimeout;

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
    await _writeKeys(_toStored(keys.stored));
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

    // A pre-core account still signs in with the raw password. Send it only
    // when the server says this email is one: on any other account a typo
    // (or a password from another site) would otherwise reach Supabase.
    if (!await _backend.needsLegacySignIn(email.trim())) {
      throw const InvalidCredentials();
    }
    await _backend.signIn(email, password); // throws InvalidCredentials
    final profile = await _backend.fetchProfile();

    if (profile?.keys != null) {
      // An earlier upgrade stored v2 keys but failed before switching the
      // auth password. Finish it.
      final unlocked = await _unlock(password, profile!.keys!);
      final creds = await KeyHierarchy.deriveCredentials(
          password: password, salt: salt, params: params);
      await _backend.updateAuthPassword(creds.authSecret);
      await _markAuthUpgraded();
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
    await _writeKeys(_toStored(keys.stored, legacyDek: true));
    await _backend.updateAuthPassword(keys.authSecret);
    await _markAuthUpgraded();
    return UnlockResult(
      dek: keys.dek,
      legacyDek: true,
      newRecoveryKey: keys.recoveryKey,
    );
  }

  /// Re-derive the DEK for an already signed-in session (app relaunch).
  /// Works offline: when the server can't be reached in [onlineTimeout], the
  /// device's copy of the keys from the last successful fetch is used.
  Future<UnlockResult> unlock(String password) async {
    StoredKeys? keys;
    try {
      keys = await _fetchKeys().timeout(onlineTimeout);
    } on Object {
      keys = await _cachedKeys();
      if (keys == null) rethrow;
    }
    if (keys == null) throw const KeyMismatch();
    return _unlock(password, keys);
  }

  /// The device has biometrics that can hold the key.
  Future<bool> biometricsAvailable() async =>
      await _biometrics?.isAvailable() ?? false;

  /// Biometric unlock is turned on for the signed-in user on this device.
  Future<bool> biometricsEnabled() async {
    final userId = _backend.currentUserId;
    if (userId == null || _biometrics == null) return false;
    return _biometrics.isEnabled(userId);
  }

  /// Turn on biometric unlock. The password proves it's the owner holding
  /// the phone, and yields the DEK to store behind biometrics.
  Future<void> enableBiometrics(String password) async {
    final store = _biometrics;
    if (store == null || !await store.isAvailable()) {
      throw StateError('Biometric unlock is not available on this device.');
    }
    final unlocked = await unlock(password);
    try {
      await store.save(
        _requireUserId(),
        (dek: unlocked.dek, legacyDek: unlocked.legacyDek),
      );
    } finally {
      unlocked.dek.fillRange(0, unlocked.dek.length, 0);
    }
  }

  Future<void> disableBiometrics() async {
    final userId = _backend.currentUserId;
    if (userId != null) await _biometrics?.clear(userId);
  }

  /// Prompts for biometrics. Null when the user cancels. Throws
  /// [BiometricKeyInvalidated] when the OS dropped the key (new fingerprint
  /// or face enrolled); the user then unlocks with the password and can
  /// turn biometrics on again.
  Future<UnlockResult?> unlockWithBiometrics() async {
    final store = _biometrics;
    if (store == null) return null;
    final secret = await store.read(_requireUserId());
    if (secret == null) return null;
    return UnlockResult(dek: secret.dek, legacyDek: secret.legacyDek);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final keys = await _fetchKeys();
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
    final keys = await _fetchKeys();
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
    final keys = await _fetchKeys();
    if (keys == null) throw const KeyMismatch();
    final rotated =
        await KeyHierarchy.rotateRecoveryKey(dek: dek, stored: _wrapped(keys));
    await _writeKeys(
        keys.copyWith(recoveryWrappedDek: rotated.stored.recoveryWrappedDek));
    return rotated.recoveryKey;
  }

  /// Signs out and forgets this device's copy of the keys, including the
  /// biometric one.
  Future<void> signOut() async {
    await _forgetDevice();
    await _backend.signOut();
  }

  /// The signed-in account's email, if any.
  String? get currentEmail => _backend.currentEmail;

  /// The signed-in account's id, if any.
  String? get currentUserId => _backend.currentUserId;

  /// First half of "forgot password". [redirectTo] is the app's deep link.
  Future<void> sendPasswordReset(String email, {String? redirectTo}) =>
      _backend.sendPasswordReset(email.trim(), redirectTo: redirectTo);

  Future<void> deleteAccount() async {
    final userId = _backend.currentUserId;
    await _backend.deleteAccount();
    if (userId != null) {
      await _cache.clear(userId);
      await _biometrics?.clear(userId);
    }
  }

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
      await _writeKeys(_toStored(created.stored));
      if (authParams != params) await _setPassword(created.dek, password);
      return UnlockResult(
          dek: created.dek, newRecoveryKey: created.recoveryKey);
    }

    if (keys.legacyDek && !profile!.authUpgraded) {
      // An upgrade switched the auth password but didn't record it.
      await _markAuthUpgraded();
    }
    await _cache.write(_requireUserId(), keys);
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
    final keys = await _fetchKeys();
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
    await _writeKeys(pending);
    await _backend.updateAuthPassword(rewrapped.authSecret);
    await _writeKeys(_promote(pending));
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
      try {
        await _writeKeys(promoted);
      } on Object {
        // Offline: the promotion is idempotent and happens next time.
      }
      return UnlockResult(dek: dek, legacyDek: keys.legacyDek);
    } on Exception {
      throw const KeyMismatch();
    }
  }

  /// The server's key row, also saved as this device's copy.
  Future<StoredKeys?> _fetchKeys() async {
    final keys = (await _backend.fetchProfile())?.keys;
    final userId = _backend.currentUserId;
    if (keys != null && userId != null) await _cache.write(userId, keys);
    return keys;
  }

  Future<StoredKeys?> _cachedKeys() async {
    final userId = _backend.currentUserId;
    return userId == null ? null : _cache.read(userId);
  }

  Future<void> _writeKeys(StoredKeys keys) async {
    await _backend.writeKeys(keys);
    await _cache.write(_requireUserId(), keys);
  }

  /// Best effort: if it fails, the next v2 sign-in records it (_afterAuth).
  Future<void> _markAuthUpgraded() async {
    try {
      await _backend.markAuthUpgraded();
    } on Object {
      // See above.
    }
  }

  Future<void> _forgetDevice() async {
    final userId = _backend.currentUserId;
    if (userId == null) return;
    await _cache.clear(userId);
    await _biometrics?.clear(userId);
  }

  String _requireUserId() {
    final id = _backend.currentUserId;
    if (id == null) throw StateError('Not signed in');
    return id;
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
