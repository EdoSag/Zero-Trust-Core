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

  @override
  Future<void> signIn(String email, String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    if (authPasswords[email] != authPassword) throw const InvalidCredentials();
    _user = email;
  }

  /// Mirrors `zt_needs_legacy_sign_in`: a pre-core salt, and the auth
  /// password not yet switched.
  @override
  Future<bool> needsLegacySignIn(String email) async {
    final p = profiles[email];
    return p != null &&
        p.legacySalt != null &&
        !p.authUpgraded &&
        (p.keys == null || p.keys!.legacyDek);
  }

  @override
  Future<void> markAuthUpgraded() async {
    final p = profiles[_user!]!;
    profiles[_user!] = ProfileRecord(
        legacySalt: p.legacySalt, keys: p.keys, authUpgraded: true);
  }

  /// Simulates no network for profile reads.
  bool offline = false;

  @override
  Future<void> signUp(String email, String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    authPasswords[email] = authPassword;
    _user = email;
  }

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
    authPasswords.remove(_user);
    profiles.remove(_user);
    _user = null;
  }
}
