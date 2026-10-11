import 'dart:typed_data';

/// Raised by an [AccountBackend] when email + auth password are rejected.
class InvalidCredentials implements Exception {
  const InvalidCredentials();
  @override
  String toString() => 'InvalidCredentials';
}

/// The `profiles` row as the core reads it. Byte columns are raw bytes here;
/// the Supabase implementation handles PostgREST's `\x…` hex encoding.
class ProfileRecord {
  const ProfileRecord({
    this.legacySalt,
    this.keyVersion = 1,
    this.kdfSalt,
    this.kdfParams,
    this.wrappedDek,
    this.recoveryWrappedDek,
  });

  /// Pre-core `salt` column, any base64 dialect.
  final String? legacySalt;
  final int keyVersion;
  final Uint8List? kdfSalt;
  final Map<String, Object?>? kdfParams;
  final Uint8List? wrappedDek;
  final Uint8List? recoveryWrappedDek;

  bool get isV2 =>
      keyVersion >= 2 &&
      kdfSalt != null &&
      kdfParams != null &&
      wrappedDek != null &&
      recoveryWrappedDek != null;
}

/// Everything the account layer needs from the server. Supabase in
/// production; an in-memory fake in tests.
abstract interface class AccountBackend {
  String? get currentUserId;
  String? get currentEmail;

  /// Throws [InvalidCredentials] when rejected.
  Future<void> signIn(String email, String authPassword);

  /// Must leave a signed-in session (email confirmation off, or confirmed).
  Future<void> signUp(String email, String authPassword);

  Future<void> updateAuthPassword(String authPassword);
  Future<void> signOut();

  Future<ProfileRecord?> fetchProfile();
  Future<void> writeV2Keys({
    required Uint8List kdfSalt,
    required Map<String, Object?> kdfParams,
    required Uint8List wrappedDek,
    required Uint8List recoveryWrappedDek,
  });

  /// Deletes the auth user server-side; every user row cascades.
  Future<void> deleteAccount();
}
