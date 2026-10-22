import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_backend.dart';

/// The device's copy of the signed-in user's `profiles` key row, so the
/// vault unlocks without a network round trip (offline, or a slow link).
///
/// Nothing stored here is secret on its own: the DEK inside is sealed under
/// the password-derived KEK and under the recovery key. A tampered copy can
/// only fail to unlock, never unlock with the wrong key.
abstract interface class KeyCache {
  Future<StoredKeys?> read(String userId);
  Future<void> write(String userId, StoredKeys keys);
  Future<void> clear(String userId);
}

class InMemoryKeyCache implements KeyCache {
  final Map<String, StoredKeys> _keys = {};

  @override
  Future<StoredKeys?> read(String userId) async => _keys[userId];

  @override
  Future<void> write(String userId, StoredKeys keys) async =>
      _keys[userId] = keys;

  @override
  Future<void> clear(String userId) async => _keys.remove(userId);
}

/// [KeyCache] in the platform keychain / keystore.
class SecureStorageKeyCache implements KeyCache {
  SecureStorageKeyCache([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String userId) => 'zt_keys_$userId';

  @override
  Future<StoredKeys?> read(String userId) async {
    try {
      final raw = await _storage.read(key: _key(userId));
      if (raw == null) return null;
      return StoredKeys.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      // A cache that can't be read is just a cache miss.
      return null;
    }
  }

  @override
  Future<void> write(String userId, StoredKeys keys) =>
      _storage.write(key: _key(userId), value: jsonEncode(keys.toJson()));

  @override
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));
}
