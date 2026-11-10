import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:test/test.dart';
import 'package:zt_crypto/src/fast_pbkdf2.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('RFC 7914 PBKDF2-HMAC-SHA256 vectors', () {
    expect(
      _hex(pbkdf2HmacSha256Password(
          password: 'passwd',
          salt: 'salt'.codeUnits,
          iterations: 1,
          length: 64)),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
      '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
    );
    expect(
      _hex(pbkdf2HmacSha256Password(
          password: 'Password',
          salt: 'NaCl'.codeUnits,
          iterations: 80000,
          length: 64)),
      '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
      'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
    );
  });

  test('matches DartPbkdf2 for random passwords, salts and lengths', () async {
    final r = Random(7);
    for (var n = 0; n < 100; n++) {
      // Includes passwords longer than a SHA-256 block and non-ASCII text.
      final password = String.fromCharCodes(
          List.generate(r.nextInt(100), (_) => 32 + r.nextInt(500)));
      final salt = List.generate(r.nextInt(80), (_) => r.nextInt(256));
      final iterations = 1 + r.nextInt(40);
      final length = 8 + r.nextInt(80);
      final expected = await (await DartPbkdf2(
        macAlgorithm: const DartHmac(DartSha256()),
        iterations: iterations,
        bits: length * 8,
      ).deriveKeyFromPassword(password: password, nonce: salt))
          .extractBytes();
      expect(
        pbkdf2HmacSha256Password(
            password: password,
            salt: salt,
            iterations: iterations,
            length: length),
        expected,
        reason: 'case $n',
      );
    }
  });
}
