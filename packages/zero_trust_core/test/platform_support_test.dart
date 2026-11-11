import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    test('biometric unlock is off on ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(SecureBiometricKeyStore.platformSupported, isFalse);
      expect(await SecureBiometricKeyStore().isAvailable(), isFalse);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('biometric unlock is offered on ${platform.name}', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(SecureBiometricKeyStore.platformSupported, isTrue);
    });
  }
}
