import 'dart:typed_data';

import 'package:zero_trust_core/zero_trust_core.dart';

const fast = KdfParams(iterations: 1000);

/// In-memory stand-in for Supabase Auth + the `profiles` table. Records every
/// password the "server" ever receives, so tests can assert it never sees
/// the real one.
class FakeBackend implements AccountBackend {
  final Map<String, String> authPasswords = {};
  final Map<String, ProfileRecord> profiles = {};
  final List<String> passwordsSeenByServer = [];
  String? _user;
  bool failNextPasswordUpdate = false;

  /// Fail the Nth next key write (0 = the very next one); -1 = never.
  int failWritesAfter = -1;

  @override
  String? get currentUserId => _user;
  @override
  String? get currentEmail => _user;

  /// Email confirmation on: sign-up leaves no session until [confirm].
  bool requireConfirmation = false;
  final Set<String> unconfirmed = {};
  final List<String> confirmationsResent = [];
  int otherDeviceSignOuts = 0;

  /// Successful sign-ins, including re-authentication.
  int signIns = 0;

  /// Sign-ins since the last [deleteAccount]-guarding check, like a fresh
  /// session the delete-account function requires.
  bool freshSession = false;

  void confirm(String email) => unconfirmed.remove(email);

  @override
  Future<void> signIn(String email, String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    if (authPasswords[email] != authPassword) throw const InvalidCredentials();
    if (unconfirmed.contains(email)) throw const EmailNotConfirmed();
    _user = email;
    signIns++;
    freshSession = true;
  }

  /// An account made by a pre-core app version, as its first core sign-in
  /// left it: the old PBKDF2 key is the data key (`legacy_dek`) and the
  /// auth password is the derived secret. [upgraded] false is an upgrade
  /// that switched the password but didn't record it. Returns the old key.
  Future<Uint8List> seedUpgradedLegacyAccount(
    String email,
    String password, {
    KdfParams params = fast,
    bool upgraded = true,
    String Function(List<int>) encodeSalt = ZtBase64.encode,
  }) async {
    final legacySalt = Kdf.newSalt();
    final keys = await KeyHierarchy.migrateLegacyAccount(
      password: password,
      legacySalt: encodeSalt(legacySalt),
      salt: await Kdf.saltForEmail(email),
      legacyParams: params,
      params: params,
    );
    authPasswords[email] = keys.authSecret;
    profiles[email] = ProfileRecord(
      legacySalt: encodeSalt(legacySalt),
      authUpgraded: upgraded,
      keys: StoredKeys(
        kdfSalt: Uint8List.fromList(keys.stored.kdfSalt),
        kdfParams: keys.stored.kdfParams.toJson(),
        wrappedDek: keys.stored.wrappedDek,
        recoveryWrappedDek: keys.stored.recoveryWrappedDek,
        legacyDek: true,
      ),
    );
    return Uint8List.fromList(keys.dek);
  }

  /// Mirrors `zt_needs_legacy_sign_in`, retired (Z21): always false.
  int legacyLookups = 0;
  @override
  Future<bool> needsLegacySignIn(String email) async {
    legacyLookups++;
    return false;
  }

  @override
  Future<void> markAuthUpgraded() async {
    final p = profiles[_user!]!;
    profiles[_user!] = ProfileRecord(
        legacySalt: p.legacySalt, keys: p.keys, authUpgraded: true);
  }

  /// Simulates no network for profile reads.
  bool offline = false;

  /// Thrown by the next [signUp], which then creates nothing: what the
  /// server does when it can't send the confirmation email.
  Object? failNextSignUp;

  @override
  Future<bool> signUp(String email, String authPassword,
      {String? redirectTo}) async {
    passwordsSeenByServer.add(authPassword);
    final failure = failNextSignUp;
    if (failure != null) {
      failNextSignUp = null;
      throw failure;
    }
    authPasswords[email] = authPassword;
    if (requireConfirmation) {
      unconfirmed.add(email);
      return false;
    }
    _user = email;
    return true;
  }

  @override
  Future<void> resendConfirmation(String email, {String? redirectTo}) async =>
      confirmationsResent.add(email);

  @override
  Future<void> signOutOtherDevices() async => otherDeviceSignOuts++;

  @override
  Future<void> updateAuthPassword(String authPassword) async {
    if (failNextPasswordUpdate) {
      failNextPasswordUpdate = false;
      throw Exception('network');
    }
    passwordsSeenByServer.add(authPassword);
    authPasswords[_user!] = authPassword;
  }

  @override
  Future<void> signOut() async => _user = null;

  final List<String> resetEmailsSent = [];

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) async =>
      resetEmailsSent.add(email);

  @override
  Future<ProfileRecord?> fetchProfile() async {
    if (offline) throw Exception('offline');
    return profiles[_user];
  }

  @override
  Future<void> writeKeys(StoredKeys keys) async {
    if (failWritesAfter == 0) {
      failWritesAfter = -1;
      throw Exception('network');
    }
    if (failWritesAfter > 0) failWritesAfter--;
    if (offline) throw Exception('offline');
    profiles[_user!] = ProfileRecord(
      legacySalt: profiles[_user]?.legacySalt,
      keys: keys,
      authUpgraded: profiles[_user]?.authUpgraded ?? false,
    );
  }

  @override
  Future<void> deleteAccount() async {
    if (!freshSession) throw Exception('recent sign-in required');
    authPasswords.remove(_user);
    profiles.remove(_user);
    _user = null;
  }
}

/// [FakeBackend] with the server's 7-day deletion grace (Z22): deleting
/// only schedules it, and the account keeps working until then.
class GraceFakeBackend extends FakeBackend implements AccountLifecycleBackend {
  final Map<String, DateTime> scheduled = {};
  DateTime now = DateTime.utc(2026, 11, 22, 12);

  @override
  Future<DateTime> requestDeletion() async {
    if (!freshSession) throw Exception('recent sign-in required');
    final user = currentUserId!;
    final when = scheduled[user] ??= now.add(const Duration(days: 7));
    await signOut();
    return when;
  }

  @override
  Future<DateTime?> pendingDeletion() async {
    if (offline) throw Exception('offline');
    return scheduled[currentUserId];
  }

  @override
  Future<bool> keepAccount() async =>
      !purging.contains(currentUserId) &&
      scheduled.remove(currentUserId) != null;

  /// Accounts the hourly purge has claimed: too late to keep.
  final Set<String?> purging = {};

  // Email change (Z14). Users keep their first email as their id; the
  // sign-in address can differ after a change.
  final Map<String, String> emailOf = {};
  final Map<String, ({String email, String code})> pendingEmail = {};
  final List<String> codesSent = [];
  int emailCodeTries = 0;

  @override
  String? get currentEmail =>
      currentUserId == null ? null : emailOf[currentUserId] ?? currentUserId;

  String? _userFor(String email) {
    for (final e in emailOf.entries) {
      if (e.value == email) return e.key;
    }
    // An id whose address moved on no longer signs in.
    return emailOf.containsKey(email) ? null : email;
  }

  @override
  Future<void> signIn(String email, String authPassword) async {
    final user = _userFor(email);
    if (user == null) {
      passwordsSeenByServer.add(authPassword);
      throw const InvalidCredentials();
    }
    return super.signIn(user, authPassword);
  }

  @override
  Future<void> startEmailChange(String newEmail) async {
    if (!freshSession) throw Exception('recent sign-in required');
    if (_userFor(newEmail) != null &&
        authPasswords.containsKey(_userFor(newEmail))) {
      throw const EmailInUse();
    }
    final code = '${123456 + codesSent.length}';
    codesSent.add(code);
    pendingEmail[currentUserId!] = (email: newEmail, code: code);
  }

  @override
  Future<String> finishEmailChange(String code, String authSecret) async {
    final user = currentUserId!;
    final pending = pendingEmail[user];
    if (pending == null || emailCodeTries >= 5) {
      throw const EmailChangeExpired();
    }
    if (pending.code != code) {
      emailCodeTries++;
      throw const EmailChangeCodeWrong();
    }
    // One server step: the address and the sign-in secret together.
    emailOf[user] = pending.email;
    passwordsSeenByServer.add(authSecret);
    authPasswords[user] = authSecret;
    pendingEmail.remove(user);
    return pending.email;
  }
}

/// One "server" seen by several apps on the same phone, for "sign in once
/// per phone" (S-2): accounts and one-time sign-in tokens are shared, each
/// app has its own session.
class HandoffServer {
  final Map<String, String> authPasswords = {};
  final Map<String, ProfileRecord> profiles = {};

  /// Token -> user. A token works once.
  final Map<String, String> tokens = {};
  int tokensMade = 0;

  /// Makes the next [HandoffFakeBackend.handoffToken] fail like an
  /// undeployed function.
  bool functionMissing = false;
}

/// [FakeBackend] that can hand its session to another app (S-2), on a
/// [HandoffServer] shared with the other apps' backends.
class HandoffFakeBackend extends FakeBackend implements AccountHandoffBackend {
  HandoffFakeBackend(this.server);
  final HandoffServer server;

  @override
  Map<String, String> get authPasswords => server.authPasswords;
  @override
  Map<String, ProfileRecord> get profiles => server.profiles;

  @override
  Future<String> handoffToken() async {
    if (server.functionMissing) throw Exception('404 function not found');
    final user = currentUserId;
    if (user == null) throw Exception('401');
    final token = 'token-${server.tokensMade++}';
    server.tokens[token] = user;
    return token;
  }

  @override
  Future<void> signInWithHandoffToken(String tokenHash) async {
    final user = server.tokens.remove(tokenHash);
    if (user == null) throw Exception('token expired or used');
    _user = user;
  }
}
