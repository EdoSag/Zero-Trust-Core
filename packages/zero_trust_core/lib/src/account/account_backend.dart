import 'dart:typed_data';

/// Raised by an [AccountBackend] when email + auth password are rejected.
class InvalidCredentials implements Exception {
  const InvalidCredentials();
  @override
  String toString() => 'InvalidCredentials';
}

/// The v2 key columns of a `profiles` row. Byte columns are raw bytes here;
/// the Supabase implementation handles PostgREST's `\x…` hex encoding.
class StoredKeys {
  const StoredKeys({
    required this.kdfSalt,
    required this.kdfParams,
    required this.wrappedDek,
    required this.recoveryWrappedDek,
    this.legacyDek = false,
    this.pendingWrappedDek,
    this.pendingKdfParams,
  });

  final Uint8List kdfSalt;
  final Map<String, Object?> kdfParams;
  final Uint8List wrappedDek;
  final Uint8List recoveryWrappedDek;

  /// The DEK is a pre-core PBKDF2 key adopted at upgrade, so existing
  /// ciphertext was written with it directly rather than with an app key.
  final bool legacyDek;

  /// The DEK wrapped for a password change that may not have finished:
  /// written before the auth password changes, promoted after. Lets an
  /// interrupted change complete on the next unlock instead of locking the
  /// user out.
  final Uint8List? pendingWrappedDek;
  final Map<String, Object?>? pendingKdfParams;

  StoredKeys copyWith({
    Map<String, Object?>? kdfParams,
    Uint8List? wrappedDek,
    Uint8List? recoveryWrappedDek,
    Uint8List? pendingWrappedDek,
    Map<String, Object?>? pendingKdfParams,
    bool clearPending = false,
  }) =>
      StoredKeys(
        kdfSalt: kdfSalt,
        kdfParams: kdfParams ?? this.kdfParams,
        wrappedDek: wrappedDek ?? this.wrappedDek,
        recoveryWrappedDek: recoveryWrappedDek ?? this.recoveryWrappedDek,
        legacyDek: legacyDek,
        pendingWrappedDek:
            clearPending ? null : pendingWrappedDek ?? this.pendingWrappedDek,
        pendingKdfParams:
            clearPending ? null : pendingKdfParams ?? this.pendingKdfParams,
      );
}

/// The `profiles` row as the core reads it.
class ProfileRecord {
  const ProfileRecord({this.legacySalt, this.keys});

  /// Pre-core `salt` column, any base64 dialect.
  final String? legacySalt;

  /// Null until the account has v2 keys.
  final StoredKeys? keys;
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
  Future<void> writeKeys(StoredKeys keys);

  /// Deletes the auth user server-side; every user row cascades.
  Future<void> deleteAccount();
}
