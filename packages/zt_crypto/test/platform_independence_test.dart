import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

/// Stands in for `cryptography_flutter` on Android: its HMAC goes through
/// javax.crypto, which throws on an empty key.
class _EmptyKeyRejectingHmac extends DartHmac {
  const _EmptyKeyRejectingHmac(super.hashAlgorithm);

  @override
  Future<Mac> calculateMac(
    List<int> bytes, {
    required SecretKey secretKey,
    List<int> nonce = const <int>[],
    List<int> aad = const <int>[],
  }) async {
    if ((await secretKey.extractBytes()).isEmpty) {
      throw ArgumentError('Empty key');
    }
    return super.calculateMac(bytes, secretKey: secretKey, nonce: nonce);
  }
}

class _PlatformLikeCryptography extends DartCryptography {
  @override
  Hmac hmac(HashAlgorithm hashAlgorithm) =>
      _EmptyKeyRejectingHmac(hashAlgorithm);
}

void main() {
  test('key derivation ignores the app-wide Cryptography instance', () async {
    const params = KdfParams(iterations: 1000);
    final salt = await Kdf.saltForEmail('someone@example.com');
    final expected = await KeyHierarchy.deriveCredentials(
        password: 'correct horse battery', salt: salt, params: params);

    final previous = Cryptography.instance;
    Cryptography.instance = _PlatformLikeCryptography();
    addTearDown(() => Cryptography.instance = previous);

    // Sanity check: the stand-in really fails the way Android did.
    await expectLater(
      Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(secretKey: SecretKey([1, 2, 3]), nonce: const []),
      throwsArgumentError,
    );

    final actual = await KeyHierarchy.deriveCredentials(
        password: 'correct horse battery', salt: salt, params: params);
    expect(actual.authSecret, expected.authSecret);
    expect(actual.kek, expected.kek);
    expect(await Kdf.saltForEmail('someone@example.com'), salt);
  });
}
