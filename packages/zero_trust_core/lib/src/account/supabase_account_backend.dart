import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_backend.dart';

/// [AccountBackend] over the shared `zerotrust_apps` Supabase project.
class SupabaseAccountBackend implements AccountBackend {
  SupabaseAccountBackend([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<void> signIn(String email, String authPassword) async {
    try {
      await _client.auth
          .signInWithPassword(email: email, password: authPassword);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials' ||
          e.message.contains('Invalid login credentials')) {
        throw const InvalidCredentials();
      }
      rethrow;
    }
  }

  @override
  Future<void> signUp(String email, String authPassword) async {
    final res = await _client.auth.signUp(email: email, password: authPassword);
    if (res.session == null) {
      throw StateError(
        'Sign-up needs a session. Turn off email confirmation in Supabase Auth, '
        'or sign in after confirming.',
      );
    }
  }

  @override
  Future<void> updateAuthPassword(String authPassword) =>
      _client.auth.updateUser(UserAttributes(password: authPassword));

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  @override
  Future<ProfileRecord?> fetchProfile() async {
    final row = await _client
        .from('profiles')
        .select('salt, key_version, kdf_salt, kdf_params, wrapped_dek, '
            'recovery_wrapped_dek, legacy_dek, pending_wrapped_dek, pending_kdf_params')
        .eq('id', _requireUserId())
        .maybeSingle();
    if (row == null) return null;
    final kdfSalt = _fromBytea(row['kdf_salt'] as String?);
    final kdfParams = (row['kdf_params'] as Map?)?.cast<String, Object?>();
    final wrappedDek = _fromBytea(row['wrapped_dek'] as String?);
    final recoveryWrappedDek =
        _fromBytea(row['recovery_wrapped_dek'] as String?);
    final hasKeys = ((row['key_version'] as int?) ?? 1) >= 2 &&
        kdfSalt != null &&
        kdfParams != null &&
        wrappedDek != null &&
        recoveryWrappedDek != null;
    return ProfileRecord(
      legacySalt: row['salt'] as String?,
      keys: hasKeys
          ? StoredKeys(
              kdfSalt: kdfSalt,
              kdfParams: kdfParams,
              wrappedDek: wrappedDek,
              recoveryWrappedDek: recoveryWrappedDek,
              legacyDek: (row['legacy_dek'] as bool?) ?? false,
              pendingWrappedDek:
                  _fromBytea(row['pending_wrapped_dek'] as String?),
              pendingKdfParams:
                  (row['pending_kdf_params'] as Map?)?.cast<String, Object?>(),
            )
          : null,
    );
  }

  @override
  Future<void> writeKeys(StoredKeys keys) => _client.from('profiles').upsert({
        'id': _requireUserId(),
        'key_version': 2,
        'kdf_salt': _toBytea(keys.kdfSalt),
        'kdf_params': keys.kdfParams,
        'wrapped_dek': _toBytea(keys.wrappedDek),
        'recovery_wrapped_dek': _toBytea(keys.recoveryWrappedDek),
        'legacy_dek': keys.legacyDek,
        'pending_wrapped_dek': keys.pendingWrappedDek == null
            ? null
            : _toBytea(keys.pendingWrappedDek!),
        'pending_kdf_params': keys.pendingKdfParams,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  @override
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    await _client.auth.signOut();
  }

  String _requireUserId() {
    final id = currentUserId;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  // PostgREST sends bytea as a `\x`-prefixed hex string.
  static String _toBytea(Uint8List bytes) =>
      '\\x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  static Uint8List? _fromBytea(String? value) {
    if (value == null) return null;
    final hex = value.startsWith('\\x') ? value.substring(2) : value;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}
