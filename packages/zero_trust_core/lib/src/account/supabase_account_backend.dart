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
      await _client.auth.signInWithPassword(email: email, password: authPassword);
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
  Future<ProfileRecord?> fetchProfile() async {
    final row = await _client
        .from('profiles')
        .select(
            'salt, key_version, kdf_salt, kdf_params, wrapped_dek, recovery_wrapped_dek')
        .eq('id', _requireUserId())
        .maybeSingle();
    if (row == null) return null;
    return ProfileRecord(
      legacySalt: row['salt'] as String?,
      keyVersion: (row['key_version'] as int?) ?? 1,
      kdfSalt: _fromBytea(row['kdf_salt'] as String?),
      kdfParams: (row['kdf_params'] as Map?)?.cast<String, Object?>(),
      wrappedDek: _fromBytea(row['wrapped_dek'] as String?),
      recoveryWrappedDek: _fromBytea(row['recovery_wrapped_dek'] as String?),
    );
  }

  @override
  Future<void> writeV2Keys({
    required Uint8List kdfSalt,
    required Map<String, Object?> kdfParams,
    required Uint8List wrappedDek,
    required Uint8List recoveryWrappedDek,
  }) =>
      _client.from('profiles').upsert({
        'id': _requireUserId(),
        'key_version': 2,
        'kdf_salt': _toBytea(kdfSalt),
        'kdf_params': kdfParams,
        'wrapped_dek': _toBytea(wrappedDek),
        'recovery_wrapped_dek': _toBytea(recoveryWrappedDek),
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
