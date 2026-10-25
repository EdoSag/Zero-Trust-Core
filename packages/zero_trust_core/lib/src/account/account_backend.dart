import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

/// Raised by an [AccountBackend] when email + auth password are rejected.
class InvalidCredentials implements Exception {
  const InvalidCredentials();
  @override
  String toString() => 'InvalidCredentials';
}

/// Sign-in was refused because the email address hasn't been confirmed
/// yet. `AccountService.resendConfirmation` sends the link again.
class EmailNotConfirmed implements Exception {
  const EmailNotConfirmed();
  @override
  String toString() => 'EmailNotConfirmed';
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

  /// For the on-device copy in a `KeyCache`. Nothing here is secret on its
  /// own: every key inside is sealed.
  Map<String, Object?> toJson() => {
        'kdf_salt': ZtBase64.encode(kdfSalt),
        'kdf_params': kdfParams,
        'wrapped_dek': ZtBase64.encode(wrappedDek),
        'recovery_wrapped_dek': ZtBase64.encode(recoveryWrappedDek),
        'legacy_dek': legacyDek,
        if (pendingWrappedDek != null)
          'pending_wrapped_dek': ZtBase64.encode(pendingWrappedDek!),
        if (pendingKdfParams != null) 'pending_kdf_params': pendingKdfParams,
      };

  factory StoredKeys.fromJson(Map<String, Object?> json) {
    final pending = json['pending_wrapped_dek'] as String?;
    return StoredKeys(
      kdfSalt: ZtBase64.decode(json['kdf_salt']! as String),
      kdfParams: (json['kdf_params']! as Map).cast<String, Object?>(),
      wrappedDek: ZtBase64.decode(json['wrapped_dek']! as String),
      recoveryWrappedDek:
          ZtBase64.decode(json['recovery_wrapped_dek']! as String),
      legacyDek: json['legacy_dek'] as bool? ?? false,
      pendingWrappedDek: pending == null ? null : ZtBase64.decode(pending),
      pendingKdfParams:
          (json['pending_kdf_params'] as Map?)?.cast<String, Object?>(),
    );
  }
}

/// The `profiles` row as the core reads it.
class ProfileRecord {
  const ProfileRecord({this.legacySalt, this.keys, this.authUpgraded = false});

  /// Pre-core `salt` column, any base64 dialect.
  final String? legacySalt;

  /// `profiles.auth_upgraded_at` is set: the Supabase password is the
  /// derived auth secret, so the raw password must never be tried again.
  final bool authUpgraded;

  /// Null until the account has v2 keys.
  final StoredKeys? keys;
}

/// Everything the account layer needs from the server. Supabase in
/// production; an in-memory fake in tests.
abstract interface class AccountBackend {
  String? get currentUserId;
  String? get currentEmail;

  /// Throws [InvalidCredentials] when rejected, [EmailNotConfirmed] when
  /// the address isn't confirmed yet.
  Future<void> signIn(String email, String authPassword);

  /// Whether [email] belongs to a pre-core account whose Supabase password
  /// is still the raw password. Only then may the raw password be sent.
  /// False for unknown emails, so it reveals nothing about v2 accounts.
  Future<bool> needsLegacySignIn(String email);

  /// Records that the Supabase password is now the derived auth secret.
  Future<void> markAuthUpgraded();

  /// Creates the auth user. True when it is signed in right away; false
  /// when Supabase sent a confirmation email first (the user signs in after
  /// opening it). [redirectTo] is where the link leads.
  Future<bool> signUp(String email, String authPassword, {String? redirectTo});

  /// Sends the sign-up confirmation email again.
  Future<void> resendConfirmation(String email, {String? redirectTo});

  /// Ends every session of this account except this device's.
  Future<void> signOutOtherDevices();

  Future<void> updateAuthPassword(String authPassword);
  Future<void> signOut();

  /// Emails a sign-in link for "forgot password". Opening it gives a session
  /// in which `AccountService.recover` can run.
  Future<void> sendPasswordReset(String email, {String? redirectTo});

  Future<ProfileRecord?> fetchProfile();
  Future<void> writeKeys(StoredKeys keys);

  /// Deletes the auth user server-side; every user row cascades. The server
  /// refuses unless this session signed in within the last few minutes.
  Future<void> deleteAccount();
}
