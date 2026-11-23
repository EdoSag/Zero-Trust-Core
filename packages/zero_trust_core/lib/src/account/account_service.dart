import 'dart:async';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'account_backend.dart';
import 'account_handoff.dart';
import 'account_lifecycle.dart';
import '../l10n/zt_l10n.dart';
import 'biometric_key_store.dart';
import 'key_cache.dart';
import 'session_key_store.dart';

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

/// Sign-up worked and Supabase emailed a confirmation link. The user opens
/// it, then signs in; that first sign-in creates the keys and shows the
/// recovery key.
class EmailConfirmationSent implements Exception {
  const EmailConfirmationSent(this.email);
  final String email;
  @override
  String toString() => 'EmailConfirmationSent($email)';
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
    SessionKeyStore? sessionKeys,
    this.onlineTimeout = const Duration(seconds: 8),
  })  : _cache = keyCache ?? InMemoryKeyCache(),
        _biometrics = biometrics,
        _sessionKeys = sessionKeys;

  final AccountBackend _backend;
  final KeyCache _cache;
  final BiometricKeyStore? _biometrics;
  final SessionKeyStore? _sessionKeys;

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
  /// No longer used since the raw-password upgrade was retired; kept so
  /// apps that pass it still compile.
  final KdfParams legacyParams;

  /// Creates the account. With email confirmation on (it should be, so no
  /// one can register someone else's address) this throws
  /// [EmailConfirmationSent]; the keys are created at the first sign-in after
  /// the address is confirmed. [redirectTo] is where the email link leads.
  Future<UnlockResult> signUp({
    required String email,
    required String password,
    String? redirectTo,
  }) async {
    _checkPassword(password);
    final salt = await Kdf.saltForEmail(email);
    final creds = await KeyHierarchy.deriveCredentials(
        password: password, salt: salt, params: params);
    final signedIn =
        await _backend.signUp(email, creds.authSecret, redirectTo: redirectTo);
    if (!signedIn) throw EmailConfirmationSent(email.trim());
    final keys = await KeyHierarchy.createAccount(
        password: password, salt: salt, params: params, credentials: creds);
    // If this write fails, the next sign-in sees an account with no keys
    // and finishes the sign-up (see _afterAuth).
    await _writeKeys(_toStored(keys.stored));
    return UnlockResult(dek: keys.dek, newRecoveryKey: keys.recoveryKey);
  }

  /// Sends the sign-up confirmation email again.
  Future<void> resendConfirmation(String email, {String? redirectTo}) =>
      _backend.resendConfirmation(email.trim(), redirectTo: redirectTo);

  /// Signs in and unlocks.
  ///
  /// Accounts made by pre-core app versions were upgraded at their first
  /// core sign-in (their old key became the DEK, `legacyDek`), and keep
  /// working here. The raw-password fallback that did that upgrade was
  /// retired on 2026-11-22 after checking live that no account still
  /// needed it: the raw password is never sent to the server any more.
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
      return _afterAuth(password, salt, authParams: p, credentials: creds);
    }
    throw const InvalidCredentials();
  }

  /// Re-derive the DEK for an already signed-in session (app relaunch).
  /// Works offline: when the server can't be reached in [onlineTimeout], the
  /// device's copy of the keys from the last successful fetch is used.
  ///
  /// With a copy on the device, the slow key derivation runs while the
  /// server's copy is fetched instead of after it, so unlocking takes the
  /// longer of the two rather than both. The server's copy still decides:
  /// if it differs (the password was changed elsewhere), the device's
  /// result is thrown away and the server's keys are used.
  Future<UnlockResult> unlock(String password) async {
    final cached = await _cachedKeys();
    if (cached != null && cached.pendingWrappedDek == null) {
      return _unlockAlongsideFetch(password, cached);
    }
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

  Future<UnlockResult> _unlockAlongsideFetch(
      String password, StoredKeys cached) async {
    // Every failure is captured as a value right away: the attempt may be
    // discarded, and an error left on an unlistened future would surface
    // as uncaught even when the server's keys then unlock fine.
    final local = _unlock(password, cached)
        .then<Object>((r) => r, onError: (Object e) => e);
    StoredKeys? fresh;
    var reached = false;
    try {
      fresh = await _fetchKeys().timeout(onlineTimeout);
      reached = true;
    } on Object {
      // Offline or slow: the device's copy is used, as before.
    }
    if (reached && (fresh == null || !_sameWrapping(fresh, cached))) {
      // Ignore the device's attempt; the server's keys decide.
      unawaited(local.then((r) {
        if (r is UnlockResult) r.dek.fillRange(0, r.dek.length, 0);
      }));
      if (fresh == null) throw const KeyMismatch();
      return _unlock(password, fresh);
    }
    final result = await local;
    if (result is UnlockResult) return result;
    throw result;
  }

  static bool _sameWrapping(StoredKeys a, StoredKeys b) =>
      _sameBytes(a.kdfSalt, b.kdfSalt) &&
      _sameBytes(a.wrappedDek, b.wrappedDek) &&
      a.legacyDek == b.legacyDek &&
      a.pendingWrappedDek == null &&
      b.pendingWrappedDek == null &&
      KdfParams.fromJson(a.kdfParams) == KdfParams.fromJson(b.kdfParams);

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  /// Turn on biometric unlock with the key from a sign-in that just
  /// happened, so the user isn't asked for the password (and the slow key
  /// derivation) a second time. [result] is left untouched; a copy of its
  /// key is stored.
  Future<void> enableBiometricsAfterSignIn(UnlockResult result) async {
    final store = _biometrics;
    if (store == null || !await store.isAvailable()) {
      throw StateError('Biometric unlock is not available on this device.');
    }
    final dek = Uint8List.fromList(result.dek);
    try {
      await store
          .save(_requireUserId(), (dek: dek, legacyDek: result.legacyDek));
    } finally {
      dek.fillRange(0, dek.length, 0);
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

  /// "Never, even after closing the app" can be offered: the phone has a
  /// screen lock and a hardware key store.
  Future<bool> stayUnlockedAvailable() async =>
      await _sessionKeys?.isAvailable() ?? false;

  /// Keeps a copy of [dek] so the app opens without asking after it's
  /// closed (see [SessionKeyStore]). [dek] is left untouched. Best effort:
  /// if the store refuses, the app simply asks to unlock next time.
  ///
  /// Saves and removals run one at a time in the order they were asked
  /// for, and a save asked for before a [forgetSession] is dropped, so a
  /// slow save can never bring back a key that "Lock now" removed.
  Future<void> rememberSession(Uint8List dek, {bool legacyDek = false}) {
    final store = _sessionKeys;
    final userId = _backend.currentUserId;
    if (store == null || userId == null) return Future.value();
    final copy = Uint8List.fromList(dek);
    final asked = _forgets;
    return _inOrder(() async {
      try {
        if (asked != _forgets) return; // Forgotten since: don't keep it.
        if (!await store.isAvailable()) return;
        if (asked != _forgets) return;
        await store.save(userId, (dek: copy, legacyDek: legacyDek));
      } finally {
        copy.fillRange(0, copy.length, 0);
      }
    });
  }

  /// The key kept by [rememberSession], to open the vault without asking.
  /// Null when there is none, or when the phone no longer has a screen lock
  /// (the copy is then removed and the user unlocks as usual).
  Future<UnlockResult?> resumeSession() async {
    final store = _sessionKeys;
    final userId = _backend.currentUserId;
    if (store == null || userId == null) return null;
    try {
      // A "Lock now" a moment ago must win over the copy it is removing.
      await _sessionOps;
      final secret = await store.read(userId);
      if (secret == null) return null;
      if (!await store.isAvailable()) {
        secret.dek.fillRange(0, secret.dek.length, 0);
        await forgetSession();
        return null;
      }
      return UnlockResult(dek: secret.dek, legacyDek: secret.legacyDek);
    } on Object {
      return null;
    }
  }

  /// Removes the copy kept by [rememberSession]; the next open asks again.
  /// Takes effect at once for any save or [resumeSession] that follows or
  /// is still pending.
  Future<void> forgetSession() {
    final userId = _backend.currentUserId;
    final store = _sessionKeys;
    if (userId == null || store == null) return Future.value();
    _forgets++;
    return _inOrder(() => store.clear(userId));
  }

  /// Counts [forgetSession] calls, so a save asked for earlier can tell it
  /// was overtaken.
  int _forgets = 0;
  Future<void>? _sessionOps;

  Future<void> _inOrder(Future<void> Function() op) {
    final previous = _sessionOps;
    final run = previous == null ? op() : previous.then((_) => op());
    return _sessionOps = run.then<void>((_) {}, onError: (Object _) {
      // Best effort, see above.
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _checkPassword(newPassword);
    final keys = await _fetchKeys();
    if (keys == null) throw const KeyMismatch();
    final unlocked = await _unlock(currentPassword, keys);
    try {
      await _reauthenticate(currentPassword);
      await _setPassword(unlocked.dek, newPassword);
    } finally {
      unlocked.dek.fillRange(0, unlocked.dek.length, 0);
    }
    await _signOutOtherDevices();
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
    // The old recovery key was just typed in, maybe on a shared device:
    // replace it. Best effort, since the password change already finished;
    // without a new key the user can still make one in settings.
    RecoveryKey? fresh;
    try {
      fresh = await rotateRecoveryKey(dek);
    } on Object {
      fresh = null;
    }
    await _signOutOtherDevices();
    return UnlockResult(
        dek: dek, legacyDek: keys.legacyDek, newRecoveryKey: fresh);
  }

  /// A new recovery key, after checking [password] locally and with the
  /// server (so a stolen session alone can't replace it).
  Future<RecoveryKey> newRecoveryKey(String password) async {
    final keys = await _fetchKeys();
    if (keys == null) throw const KeyMismatch();
    final unlocked = await _unlock(password, keys);
    try {
      await _reauthenticate(password);
      return await rotateRecoveryKey(unlocked.dek);
    } finally {
      unlocked.dek.fillRange(0, unlocked.dek.length, 0);
    }
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
  /// biometric one and the one kept to stay unlocked.
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

  /// Deletes the account in every app. [password] is checked with the
  /// server first, which also gives the fresh sign-in the server requires,
  /// so an unattended unlocked phone or a stolen session can't do this.
  ///
  /// With a backend that has a grace period ([AccountLifecycleBackend]) the
  /// account is only scheduled for deletion; the returned time says when.
  /// Either way this device signs out and forgets its keys.
  Future<DateTime?> deleteAccount({required String password}) async {
    final userId = _backend.currentUserId;
    await _reauthenticate(password);
    final lifecycle = _lifecycle;
    DateTime? when;
    if (lifecycle != null) {
      when = await lifecycle.requestDeletion();
    } else {
      await _backend.deleteAccount();
    }
    if (userId != null) {
      await _cache.clear(userId);
      await _biometrics?.clear(userId);
      _forgets++;
      await _inOrder(() async => _sessionKeys?.clear(userId));
    }
    return when;
  }

  AccountLifecycleBackend? get _lifecycle {
    final backend = _backend;
    return backend is AccountLifecycleBackend
        ? backend as AccountLifecycleBackend
        : null;
  }

  /// When the signed-in account is set to be deleted, or null (also when
  /// the server can't be reached: this only decides whether to offer
  /// "Keep my account").
  Future<DateTime?> pendingDeletion() async {
    final lifecycle = _lifecycle;
    if (lifecycle == null || _backend.currentUserId == null) return null;
    try {
      return await lifecycle.pendingDeletion().timeout(onlineTimeout);
    } on Object {
      return null;
    }
  }

  /// Cancels a scheduled deletion of the signed-in account.
  Future<bool> keepAccount() async => await _lifecycle?.keepAccount() ?? false;

  /// The server can change the account's email (Z14).
  bool get canChangeEmail => _lifecycle != null;

  /// First step of changing the email: checks [password] on this device and
  /// with the server (a fresh sign-in, which the server requires), then has
  /// a 6-digit code emailed to [newEmail].
  Future<void> startEmailChange({
    required String password,
    required String newEmail,
  }) async {
    final lifecycle = _lifecycle;
    if (lifecycle == null) throw StateError('Email change is not available');
    final email = newEmail.trim();
    if (email.toLowerCase() == currentEmail?.toLowerCase()) {
      throw ArgumentError(ZtL10n.current.errEmailSame);
    }
    final keys = await _fetchKeys();
    if (keys == null) throw const KeyMismatch();
    final unlocked = await _unlock(password, keys);
    unlocked.dek.fillRange(0, unlocked.dek.length, 0);
    await _reauthenticate(password);
    await lifecycle.startEmailChange(email);
  }

  /// Second step: with the emailed [code], the server switches the email
  /// and the sign-in secret together, so there is never a moment when
  /// neither address signs in. The encryption keys don't change, so every
  /// app and device keeps working; other devices just sign in with the new
  /// address next time.
  Future<String> finishEmailChange({
    required String password,
    required String newEmail,
    required String code,
  }) async {
    final lifecycle = _lifecycle;
    if (lifecycle == null) throw StateError('Email change is not available');
    final creds = await KeyHierarchy.deriveCredentials(
        password: password,
        salt: await Kdf.saltForEmail(newEmail.trim()),
        params: params);
    try {
      return await lifecycle.finishEmailChange(code.trim(), creds.authSecret);
    } finally {
      creds.kek.fillRange(0, creds.kek.length, 0);
    }
  }

  AccountHandoffBackend? get _handoff {
    final backend = _backend;
    return backend is AccountHandoffBackend
        ? backend as AccountHandoffBackend
        : null;
  }

  /// This app can sign another Zero-Trust app on the phone in (S-2).
  bool get canHandOffSession => _handoff != null;

  /// What another app on this phone needs to open with this account (S-2).
  /// [proof] is the key from `ztConfirmIdentity`, so the person holding the
  /// phone just proved it's them; it is copied, not kept. With
  /// [withSession] the server also makes a one-time sign-in token, so the
  /// other app gets a session of its own.
  Future<ZtHandoffGrant> handoffGrant(
    UnlockResult proof, {
    required bool withSession,
    Duration validFor = const Duration(minutes: 2),
  }) async {
    final userId = _requireUserId();
    final email = _backend.currentEmail ?? '';
    String? token;
    if (withSession) {
      final handoff = _handoff;
      if (handoff == null) throw StateError('Handing off is not available');
      token = await handoff.handoffToken().timeout(onlineTimeout * 2);
    }
    // Signed out, or into another account, while the server answered.
    if (_backend.currentUserId != userId) throw StateError('Not signed in');
    return ZtHandoffGrant(
      userId: userId,
      email: email,
      dek: Uint8List.fromList(proof.dek),
      legacyDek: proof.legacyDek,
      tokenHash: token,
      expiresAt: DateTime.now().add(validFor),
    );
  }

  /// Signs in with what another app on this phone handed over (S-2) and
  /// unlocks, without the password. The session is this app's own. The
  /// server's key row is fetched (and kept for offline unlock) as after a
  /// password sign-in; if anything fails, this app is left signed out.
  /// [grant] is left untouched.
  Future<UnlockResult> signInWithHandoff(ZtHandoffGrant grant) async {
    final handoff = _handoff;
    final token = grant.tokenHash;
    if (handoff == null) throw StateError('Handing off is not available');
    if (token == null) throw ArgumentError('No sign-in token');
    await handoff.signInWithHandoffToken(token);
    try {
      if (_backend.currentUserId != grant.userId) {
        throw const ZtHandoffWrongAccount();
      }
      final keys = await _fetchKeys();
      if (keys == null) throw const KeyMismatch();
      return UnlockResult(
          dek: Uint8List.fromList(grant.dek), legacyDek: keys.legacyDek);
    } on Object {
      try {
        await _backend.signOut();
      } on Object {
        // Best effort: the sign-in screen stays up either way.
      }
      rethrow;
    }
  }

  /// Unlocks this app, already signed in to the same account, with the key
  /// another app on this phone handed over (S-2). Works offline. [grant] is
  /// left untouched.
  UnlockResult unlockWithHandoff(ZtHandoffGrant grant) {
    if (_backend.currentUserId != grant.userId) {
      throw const ZtHandoffWrongAccount();
    }
    return UnlockResult(
        dek: Uint8List.fromList(grant.dek), legacyDek: grant.legacyDek);
  }

  Future<UnlockResult> _afterAuth(
    String password,
    Uint8List salt, {
    required KdfParams authParams,
    required PasswordCredentials credentials,
  }) async {
    final profile = await _backend.fetchProfile();
    final keys = profile?.keys;

    if (keys == null) {
      if (profile?.legacySalt != null) throw const KeyMismatch();
      // Sign-up created the auth user but never stored keys. No data can
      // exist yet, so finish it with fresh keys; the auth secret is the one
      // just used, because it depends only on password, email and params.
      final created = await KeyHierarchy.createAccount(
          password: password,
          salt: salt,
          params: authParams,
          credentials: credentials);
      await _writeKeys(_toStored(created.stored));
      if (authParams != params) await _setPassword(created.dek, password);
      return UnlockResult(
          dek: created.dek, newRecoveryKey: created.recoveryKey);
    }

    if (keys.legacyDek && !profile!.authUpgraded) {
      // An upgrade switched the auth password but didn't record it.
      await _markAuthUpgraded();
    }
    await _cacheKeys(_requireUserId(), keys);
    final unlocked = await _unlock(password, keys);
    if (authParams != params) {
      // Signed in with an older KDF setting: move the account forward.
      await _setPassword(unlocked.dek, password);
    }
    return unlocked;
  }

  /// Signs in again with [password]: proves it to the server (not just to
  /// this device) and starts a fresh session, which the server checks before
  /// deleting the account. Like [signIn] it tries [previousParams] too, for
  /// a session that began before the app raised [params].
  Future<void> _reauthenticate(String password) async {
    final email = _backend.currentEmail;
    if (email == null) throw StateError('Not signed in');
    final salt = await Kdf.saltForEmail(email);
    for (final p in [params, ...previousParams]) {
      final creds = await KeyHierarchy.deriveCredentials(
          password: password, salt: salt, params: p);
      try {
        await _backend.signIn(email, creds.authSecret);
        return;
      } on InvalidCredentials {
        continue;
      }
    }
    throw const InvalidCredentials();
  }

  /// After a password change or recovery, so a device that had the old
  /// password (or a stolen session) loses access. Best effort: the change
  /// itself already finished.
  Future<void> _signOutOtherDevices() async {
    try {
      await _backend.signOutOtherDevices();
    } on Object {
      // See above.
    }
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
    // The data key stays wrapped under the stored salt; the sign-in secret
    // follows the account's email. They are the same salt unless the email
    // was changed (Z14), and then the secret needs a second derivation.
    final emailSalt = await Kdf.saltForEmail(email);
    final rewrapped = await KeyHierarchy.rewrapForNewPassword(
      dek: dek,
      newPassword: newPassword,
      stored: _wrapped(keys),
      salt: keys.kdfSalt,
      params: params,
    );
    final authSecret = _sameBytes(keys.kdfSalt, emailSalt)
        ? rewrapped.authSecret
        : (await KeyHierarchy.deriveCredentials(
                password: newPassword, salt: emailSalt, params: params))
            .authSecret;
    final pending = keys.copyWith(
      pendingWrappedDek: rewrapped.stored.wrappedDek,
      pendingKdfParams: params.toJson(),
    );
    await _writeKeys(pending);
    await _backend.updateAuthPassword(authSecret);
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
        await _writeKeys(promoted).timeout(onlineTimeout);
      } on Object {
        // Offline or hung: the promotion is idempotent and happens next time.
      }
      return UnlockResult(dek: dek, legacyDek: keys.legacyDek);
    } on Exception {
      throw const KeyMismatch();
    }
  }

  /// The server's key row, also saved as this device's copy.
  Future<StoredKeys?> _fetchKeys() async {
    // Captured first: a slow fetch can outlive a sign-out and a sign-in to
    // another account, and must not be cached under that account.
    final userId = _backend.currentUserId;
    final keys = (await _backend.fetchProfile())?.keys;
    if (keys != null && userId != null && userId == _backend.currentUserId) {
      await _cacheKeys(userId, keys);
    }
    return keys;
  }

  Future<StoredKeys?> _cachedKeys() async {
    final userId = _backend.currentUserId;
    return userId == null ? null : _cache.read(userId);
  }

  Future<void> _writeKeys(StoredKeys keys) async {
    final userId = _requireUserId();
    await _backend.writeKeys(keys);
    await _cacheKeys(userId, keys);
  }

  /// Best effort: a keychain that refuses the write only costs offline
  /// unlock, never a sign-in or unlock that already succeeded online.
  Future<void> _cacheKeys(String userId, StoredKeys keys) async {
    try {
      await _cache.write(userId, keys);
    } on Object {
      // See above.
    }
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
    _forgets++;
    await _inOrder(() async => _sessionKeys?.clear(userId));
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
