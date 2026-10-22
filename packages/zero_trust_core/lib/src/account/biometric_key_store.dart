import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zt_crypto/zt_crypto.dart';

/// The DEK as kept behind the device's biometrics.
typedef BiometricSecret = ({Uint8List dek, bool legacyDek});

/// The biometric copy is gone, usually because fingerprints or faces were
/// added or removed (the OS then destroys the key). The password still works.
class BiometricKeyInvalidated implements Exception {
  const BiometricKeyInvalidated();
  @override
  String toString() => 'BiometricKeyInvalidated';
}

/// Keeps the DEK in hardware-backed storage that only opens after a
/// biometric check, so a user can unlock with a fingerprint or face instead
/// of the password.
abstract interface class BiometricKeyStore {
  /// The device has enrolled biometrics that can protect a key.
  Future<bool> isAvailable();

  /// A DEK is stored for [userId]. Never prompts.
  Future<bool> isEnabled(String userId);

  Future<void> save(String userId, BiometricSecret secret);

  /// Prompts for biometrics. Null when the user cancels; throws
  /// [BiometricKeyInvalidated] when the stored key is gone.
  Future<BiometricSecret?> read(String userId);

  Future<void> clear(String userId);
}

class InMemoryBiometricKeyStore implements BiometricKeyStore {
  InMemoryBiometricKeyStore({this.available = true});

  bool available;

  /// What the next [read] prompt does: `true` succeeds, `false` cancels.
  bool approve = true;

  final Map<String, BiometricSecret> _secrets = {};
  final Set<String> _enabled = {};

  /// Simulates new biometrics being enrolled: the OS drops the key.
  void invalidate(String userId) => _secrets.remove(userId);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isEnabled(String userId) async => _enabled.contains(userId);

  @override
  Future<void> save(String userId, BiometricSecret secret) async {
    _secrets[userId] =
        (dek: Uint8List.fromList(secret.dek), legacyDek: secret.legacyDek);
    _enabled.add(userId);
  }

  @override
  Future<BiometricSecret?> read(String userId) async {
    if (!approve) return null;
    final s = _secrets[userId];
    if (s == null) {
      _enabled.remove(userId);
      throw const BiometricKeyInvalidated();
    }
    return (dek: Uint8List.fromList(s.dek), legacyDek: s.legacyDek);
  }

  @override
  Future<void> clear(String userId) async {
    _secrets.remove(userId);
    _enabled.remove(userId);
  }
}

/// [BiometricKeyStore] on the Android Keystore (strong biometrics, prompt on
/// every read) and the iOS Keychain (`biometryCurrentSet`, so enrolling a new
/// finger or face destroys the item). Android apps must use
/// `FlutterFragmentActivity`; iOS apps need `NSFaceIDUsageDescription`.
class SecureBiometricKeyStore implements BiometricKeyStore {
  SecureBiometricKeyStore({
    String promptTitle = 'Unlock',
    LocalAuthentication? localAuth,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _secure = FlutterSecureStorage(
          aOptions: AndroidOptions.biometric(
            enforceBiometrics: true,
            requireBiometricsPerOperation: true,
            biometricType: AndroidBiometricType.strongBiometricOnly,
            storageNamespace: 'zt_biometric',
            biometricPromptTitle: promptTitle,
          ),
          iOptions: const IOSOptions(
            accessibility: KeychainAccessibility.passcode,
            accessControlFlags: [AccessControlFlag.biometryCurrentSet],
          ),
        );

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secure;

  /// Whether a secret was stored, kept outside the biometric item so it can
  /// be read without a prompt.
  static const FlutterSecureStorage _markers = FlutterSecureStorage();

  static String _key(String userId) => 'zt_bio_dek_$userId';
  static String _marker(String userId) => 'zt_bio_on_$userId';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> isEnabled(String userId) async =>
      await _markers.read(key: _marker(userId)) != null;

  @override
  Future<void> save(String userId, BiometricSecret secret) async {
    await _secure.write(
      key: _key(userId),
      value: jsonEncode({
        'dek': ZtBase64.encode(secret.dek),
        'legacy': secret.legacyDek,
      }),
    );
    await _markers.write(key: _marker(userId), value: '1');
  }

  @override
  Future<BiometricSecret?> read(String userId) async {
    final String? raw;
    try {
      raw = await _secure.read(key: _key(userId));
    } on PlatformException {
      // Cancelled, too many attempts, or locked out: the password still works.
      return null;
    }
    if (raw == null) {
      await clear(userId);
      throw const BiometricKeyInvalidated();
    }
    final json = (jsonDecode(raw) as Map).cast<String, Object?>();
    return (
      dek: ZtBase64.decode(json['dek']! as String),
      legacyDek: json['legacy'] as bool? ?? false,
    );
  }

  @override
  Future<void> clear(String userId) async {
    await _markers.delete(key: _marker(userId));
    try {
      await _secure.delete(key: _key(userId));
    } on PlatformException {
      // Already gone with the invalidated key.
    }
  }
}
