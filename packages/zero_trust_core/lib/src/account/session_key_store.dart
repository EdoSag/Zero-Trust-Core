import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zt_crypto/zt_crypto.dart';

import 'biometric_key_store.dart';

/// Keeps the DEK across app restarts for users who chose "Never, even after
/// closing the app" in Auto-lock, so the app opens without asking.
///
/// The key stays in the platform's hardware-backed store (Android Keystore,
/// iOS Keychain), never in a plain file, and the data on the phone stays
/// encrypted. It only opens on a phone that has a screen lock, so a lost or
/// stolen phone still needs that screen lock first. Off unless the user
/// turns it on; sign-out, "Lock now" and any other auto-lock choice remove
/// the stored copy.
abstract interface class SessionKeyStore {
  /// The phone has a screen lock (PIN, pattern, password or biometrics),
  /// and the platform keeps the key in hardware. Without a screen lock this
  /// option would leave the app open to anyone holding the phone, so it's
  /// not offered then.
  Future<bool> isAvailable();

  Future<void> save(String userId, BiometricSecret secret);

  /// The kept key, or null when there is none. Never prompts.
  Future<BiometricSecret?> read(String userId);

  Future<void> clear(String userId);
}

class InMemorySessionKeyStore implements SessionKeyStore {
  InMemorySessionKeyStore({this.available = true});

  /// Simulates a phone with (true) or without (false) a screen lock.
  bool available;

  final Map<String, BiometricSecret> _secrets = {};

  bool has(String userId) => _secrets.containsKey(userId);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> save(String userId, BiometricSecret secret) async =>
      _secrets[userId] =
          (dek: Uint8List.fromList(secret.dek), legacyDek: secret.legacyDek);

  @override
  Future<BiometricSecret?> read(String userId) async {
    final s = _secrets[userId];
    if (s == null) return null;
    return (dek: Uint8List.fromList(s.dek), legacyDek: s.legacyDek);
  }

  @override
  Future<void> clear(String userId) async => _secrets.remove(userId);
}

/// [SessionKeyStore] in the Android Keystore and the iOS Keychain
/// (`unlocked_this_device`: readable only while the phone is unlocked, and
/// never copied to backups or another device).
class SecureSessionKeyStore implements SessionKeyStore {
  SecureSessionKeyStore({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'zt_session'),
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );

  static String _key(String userId) => 'zt_session_dek_$userId';

  @override
  Future<bool> isAvailable() async {
    if (!SecureBiometricKeyStore.platformSupported) return false;
    try {
      // True when the phone has a screen lock or enrolled biometrics.
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> save(String userId, BiometricSecret secret) => _secure.write(
        key: _key(userId),
        value: jsonEncode({
          'dek': ZtBase64.encode(secret.dek),
          'legacy': secret.legacyDek,
        }),
      );

  @override
  Future<BiometricSecret?> read(String userId) async {
    final String? raw;
    try {
      raw = await _secure.read(key: _key(userId));
    } on PlatformException {
      return null;
    }
    if (raw == null) return null;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      return (
        dek: ZtBase64.decode(json['dek']! as String),
        legacyDek: json['legacy'] as bool? ?? false,
      );
    } on Object {
      return null; // Unreadable: the user unlocks as usual.
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _secure.delete(key: _key(userId));
    } on PlatformException {
      // Already gone.
    }
  }
}
