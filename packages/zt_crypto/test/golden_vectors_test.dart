import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

/// Fixed inputs and the keys every app must derive from them. If one of these
/// fails, a dependency bump or a code change has silently changed how keys
/// are made, and existing accounts would no longer open. Don't update the
/// expected values to make a test pass.
///
/// The PBKDF2, HKDF and app-key values were checked against Python's
/// `hashlib` / `hmac` (2026-11-09), not only against this code.
void main() {
  const email = 'vector@zero-trust.test';
  const password = 'correct horse battery staple';
  const fast = KdfParams(iterations: 1000);

  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  Uint8List bytes(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  test('email salt', () async {
    expect(
        hex(await Kdf.saltForEmail(email)), '8c3fde42923154af6c393a6cb24a0dcf');
    expect(hex(await Kdf.saltForEmail('Vector@Zero-Trust.TEST')),
        '8c3fde42923154af6c393a6cb24a0dcf');
  });

  test('auth secret and KEK (1000 iterations)', () async {
    final c = await KeyHierarchy.deriveCredentials(
        password: password, salt: await Kdf.saltForEmail(email), params: fast);
    expect(c.authSecret, 'XGbet9CZv8NsekltgyS0HcJNhbe-gPYY8bpGEVKiz-8');
    expect(hex(c.kek),
        '7d3116d1fd66aad7248df427e9e3fabba3bb406db31ea3a9bec3c482c120e7ae');
  });

  test('auth secret at production strength (600k iterations)', () async {
    final c = await KeyHierarchy.deriveCredentials(
        password: password, salt: await Kdf.saltForEmail(email));
    expect(c.authSecret, '2_S6y8k7lIyIM43teyEBjt-5uBAG_aaGXxwsH7LeOac');
  });

  test('pre-core data key (PBKDF2 of the password, as the old apps did)',
      () async {
    final key = await Kdf.deriveMasterKey(
        password: password, salt: await Kdf.saltForEmail(email), params: fast);
    expect(hex(key),
        '1f4c21241f2bb0d361388f85ecf857fff78d3ba48a253f2f2b30be7a5db8af7a');
  });

  test('per-app keys and signing keys', () async {
    final dek = Uint8List.fromList(List.generate(32, (i) => i));
    const expected = {
      'notes': (
        '9f7d31ba23b1c1d8124b22f4dc7b87d83aa5b31ef2b716b2755a53f641a43926',
        'eb439239cef948b010d5a2d5153cf835c99363a8493ed127f2f9a1a13ba3d8cc',
      ),
      'tasks': (
        '72447d98b94e4b9ae5f244ec49fe2d0c32b87885e304885ee78ebf7734f933de',
        'f2af4b5166647320976992504cae86d23f58bd2e001201f8730e49b6cafc4fb8',
      ),
      'fitness': (
        '24b54d980b25e1d04e9dc1925daaac00efc463654ec0a65a3d12571b237dd4f9',
        '6650b012b083a24440bd5b423951926fb4e4199130fb063948718c6cd44c1960',
      ),
      'contacts': (
        '74bc60bd1b9c1075d45f169c415b528464ef4c3e2beb06b0680cfc6ba661a9eb',
        '27a184e6a1e2b473bdb12537d1084675f3f79d1638710640c69e7f1e22bc014a',
      ),
    };
    for (final MapEntry(key: app, value: (appKey, publicKey))
        in expected.entries) {
      final k = await KeyHierarchy.appKey(dek, app);
      expect(hex(k), appKey, reason: app);
      expect(hex((await KeyHierarchy.signingKeys(k)).publicKeyBytes), publicKey,
          reason: app);
    }
  });

  group('stored keys written by v0.7 still open', () {
    final stored = WrappedKeys(
      kdfSalt: bytes('8c3fde42923154af6c393a6cb24a0dcf'),
      kdfParams: fast,
      wrappedDek: bytes('1af8dabce1b340f66124b0b1fccfea00109889e2f343488a'
          '55acad86db89b3a2c72b88bc6ffe89d5e7cec149c5fe8423ca04149fd0331bf9'
          'ddbdd3c8'),
      recoveryWrappedDek: bytes('4beb5ffd2710ad9431627d9683172b0995195375'
          '8d46475a5f1d0abbb62e61bcb04bbd9d41f8fa296a1b7abfbd47e6ba8498f8d4'
          'ca87bc85ba9c2f99'),
    );
    const dek =
        '27c06da71e64c52c1d4e7a4fa5ee077c8c41db4b82061a3e15ccbbd08ffd6f98';

    test('with the password', () async {
      expect(
          hex(await KeyHierarchy.unlockWithPassword(
              password: password, stored: stored)),
          dek);
    });

    test('with the recovery key', () async {
      final key = await RecoveryKey.parse(
          'ZT-CGMG-PJFF-2K2H-10HG-09S9-Y832-CBBQ-90DZ-7MTH-7JVQ-R6AP-NZC3-3KQG-CJ');
      expect(
          hex(await KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: key, stored: stored)),
          dek);
    });
  });
}
