import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

const fast = KdfParams(iterations: 1000);

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);

void main() {
  group('ZtBase64', () {
    // Bytes chosen so every dialect differs: '-'/'_' vs '+'/'/', and padding.
    final bytes =
        List<int>.generate(16, (i) => [0xfb, 0xff, 0xfe, 0x3e, 0x3f][i % 5]);

    test('encodes unpadded base64url', () {
      expect(ZtBase64.encode(bytes), '-__-Pj_7__4-P_v__j4_-w');
    });

    test('decodes every dialect found in production profiles.salt', () {
      for (final variant in [
        base64Url.encode(bytes).replaceAll('=', ''), // Contacts, Tasks
        base64Url.encode(bytes), // Fitness
        base64.encode(bytes), // Notes
        ' ${base64.encode(bytes)}\n',
      ]) {
        expect(ZtBase64.decode(variant), bytes, reason: variant);
      }
    });

    test('rejects impossible lengths', () {
      expect(() => ZtBase64.decode('abcde'), throwsFormatException);
    });
  });

  group('Kdf', () {
    test('PBKDF2-HMAC-SHA256 matches RFC 7914 vector (first 32 bytes)',
        () async {
      final key = await Kdf.deriveMasterKey(
        password: 'passwd',
        salt: utf8.encode('salt'),
        params: const KdfParams(iterations: 1),
      );
      expect(hex(key),
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
    });

    test('HKDF-SHA256 matches RFC 5869 test case 3', () async {
      final okm = await Kdf.hkdf(
        unhex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
        '',
        length: 42,
      );
      expect(
          hex(okm),
          '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d'
          '9d201395faa4b61a96c8');
    });

    test('email salt is stable, case-insensitive and per-email', () async {
      final a = await Kdf.saltForEmail('Edo@Example.com ');
      expect(a, hasLength(Kdf.saltLength));
      expect(await Kdf.saltForEmail('edo@example.com'), a);
      expect(await Kdf.saltForEmail('other@example.com'), isNot(a));
    });

    test('KdfParams round-trips through JSON', () {
      expect(KdfParams.fromJson(KdfParams.current.toJson()), KdfParams.current);
    });
  });

  group('SealedBox', () {
    final key = Uint8List(32)..fillRange(0, 32, 7);

    test('round-trips and binds AAD', () async {
      final sealed = await SealedBox.sealString('hello', key, aad: [1]);
      expect(await SealedBox.openString(sealed, key, aad: [1]), 'hello');
      expect(() => SealedBox.open(sealed, key, aad: [2]),
          throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('detects tampering', () async {
      final sealed = await SealedBox.sealString('hello', key);
      sealed[14] ^= 1;
      expect(() => SealedBox.open(sealed, key),
          throwsA(isA<SecretBoxAuthenticationError>()));
    });
  });

  group('Signing', () {
    test('signs and verifies', () async {
      final keys = await Signing.generate();
      final sig = await Signing.sign([1, 2, 3], keys);
      expect(
          await Signing.verify([1, 2, 3],
              signature: sig, publicKey: keys.publicKeyBytes),
          isTrue);
      expect(
          await Signing.verify([1, 2, 4],
              signature: sig, publicKey: keys.publicKeyBytes),
          isFalse);
    });
  });

  group('RecoveryKey', () {
    test('format/parse round-trip, tolerant of case, spaces and look-alikes',
        () async {
      final key = RecoveryKey.generate();
      final text = await key.format();
      expect(text, startsWith('ZT-'));
      expect((await RecoveryKey.parse(text)).bytes, key.bytes);
      final sloppy = text
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('1', 'l')
          .replaceAll('0', 'o');
      expect((await RecoveryKey.parse(sloppy)).bytes, key.bytes);
    });

    test('catches a typo via the checksum', () async {
      final text = await RecoveryKey.generate().format();
      final i = text.length - 5;
      final typo = text.replaceRange(i, i + 1, text[i] == 'A' ? 'B' : 'A');
      expect(() => RecoveryKey.parse(typo), throwsFormatException);
    });
  });

  group('KeyHierarchy', () {
    test('new account unlocks with the password, not with a wrong one',
        () async {
      final acct = await KeyHierarchy.createAccount(
          password: 'correct horse', salt: Kdf.newSalt(), params: fast);
      expect(
          await KeyHierarchy.unlockWithPassword(
              password: 'correct horse', stored: acct.stored),
          acct.dek);
      expect(
          () => KeyHierarchy.unlockWithPassword(
              password: 'wrong', stored: acct.stored),
          throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('auth secret is deterministic but is not the KEK or the password',
        () async {
      final salt = Kdf.newSalt();
      final a = await KeyHierarchy.deriveCredentials(
          password: 'pw', salt: salt, params: fast);
      final b = await KeyHierarchy.deriveCredentials(
          password: 'pw', salt: salt, params: fast);
      expect(a.authSecret, b.authSecret);
      expect(a.authSecret, isNot(ZtBase64.encode(a.kek)));
      expect(a.authSecret, isNot('pw'));
    });

    test('recovery key unlocks the same DEK', () async {
      final acct = await KeyHierarchy.createAccount(
          password: 'pw', salt: Kdf.newSalt(), params: fast);
      final parsed = await RecoveryKey.parse(await acct.recoveryKey.format());
      expect(
          await KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: parsed, stored: acct.stored),
          acct.dek);
    });

    test('password change keeps the DEK and the recovery key', () async {
      final acct = await KeyHierarchy.createAccount(
          password: 'old', salt: Kdf.newSalt(), params: fast);
      final changed = await KeyHierarchy.rewrapForNewPassword(
          dek: acct.dek,
          newPassword: 'new',
          stored: acct.stored,
          salt: acct.stored.kdfSalt,
          params: fast);
      expect(
          await KeyHierarchy.unlockWithPassword(
              password: 'new', stored: changed.stored),
          acct.dek);
      expect(
          () => KeyHierarchy.unlockWithPassword(
              password: 'old', stored: changed.stored),
          throwsA(isA<SecretBoxAuthenticationError>()));
      expect(
          await KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: acct.recoveryKey, stored: changed.stored),
          acct.dek);
      expect(changed.authSecret, isNot(acct.authSecret));
    });

    test('rotating the recovery key invalidates the old one', () async {
      final acct = await KeyHierarchy.createAccount(
          password: 'pw', salt: Kdf.newSalt(), params: fast);
      final rotated = await KeyHierarchy.rotateRecoveryKey(
          dek: acct.dek, stored: acct.stored);
      expect(
          await KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: rotated.recoveryKey, stored: rotated.stored),
          acct.dek);
      expect(
          () => KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: acct.recoveryKey, stored: rotated.stored),
          throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('legacy migration adopts the exact key today\'s apps derive',
        () async {
      // Today Fitness/Contacts/Tasks/Notes all do PBKDF2-SHA256(password, salt).
      final legacySalt = Kdf.newSalt();
      final todaysKey = await Kdf.deriveMasterKey(
          password: 'pw', salt: legacySalt, params: fast);
      for (final saltText in [
        ZtBase64.encode(legacySalt), // written by Contacts/Tasks
        base64.encode(legacySalt), // written by Notes
      ]) {
        final migrated = await KeyHierarchy.migrateLegacyAccount(
            password: 'pw',
            legacySalt: saltText,
            salt: Kdf.newSalt(),
            legacyParams: fast,
            params: fast);
        expect(migrated.dek, todaysKey);
        expect(
            await KeyHierarchy.unlockWithPassword(
                password: 'pw', stored: migrated.stored),
            todaysKey);
      }
    });

    test('app keys are distinct per app and stable', () async {
      final dek = Kdf.randomBytes(32);
      final notes = await KeyHierarchy.appKey(dek, 'notes');
      expect(await KeyHierarchy.appKey(dek, 'notes'), notes);
      expect(await KeyHierarchy.appKey(dek, 'tasks'), isNot(notes));
      expect(() => KeyHierarchy.appKey(dek, 'Notes/../x'), throwsArgumentError);
    });

    test('production parameters (600k iterations) round-trip', () async {
      final acct =
          await KeyHierarchy.createAccount(password: 'pw', salt: Kdf.newSalt());
      expect(acct.stored.kdfParams.iterations, 600000);
      expect(
          await KeyHierarchy.unlockWithPassword(
              password: 'pw', stored: acct.stored),
          acct.dek);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
