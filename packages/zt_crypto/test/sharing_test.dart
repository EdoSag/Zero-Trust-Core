import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

Uint8List bytes(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 31 + i) & 0xff));

void main() {
  group('ZtIdentity', () {
    test('is the same for the same DEK and differs between accounts', () async {
      final a1 = await ZtIdentity.fromDek(bytes(1));
      final a2 = await ZtIdentity.fromDek(bytes(1));
      final b = await ZtIdentity.fromDek(bytes(2));
      expect(a1.public, a2.public);
      expect(a1.public == b.public, isFalse);
      expect(a1.public.dhPublic, isNot(a1.public.signPublic));
    });

    test('does not change the DEK it is derived from', () async {
      final dek = bytes(3);
      await ZtIdentity.fromDek(dek);
      expect(dek, bytes(3));
    });

    test('public identity round-trips through JSON', () async {
      final id = await ZtIdentity.fromDek(bytes(4));
      expect(ZtPublicIdentity.fromJson(id.public.toJson()), id.public);
    });

    test('signs with a key others can check', () async {
      final id = await ZtIdentity.fromDek(bytes(5));
      final sig = await id.sign([1, 2, 3]);
      expect(
          await Signing.verify([1, 2, 3],
              signature: sig, publicKey: id.public.signPublic),
          isTrue);
      expect(
          await Signing.verify([1, 2, 4],
              signature: sig, publicKey: id.public.signPublic),
          isFalse);
    });
  });

  group('KeyWrap', () {
    test('only the recipient opens it, and only in the same context', () async {
      final alice = await ZtIdentity.fromDek(bytes(10));
      final bob = await ZtIdentity.fromDek(bytes(11));
      final key = bytes(99);
      final wrapped = await KeyWrap.wrap(
          key: key, recipient: bob.public, context: 'space|s1|1|bob');

      expect(
          await KeyWrap.unwrap(
              wrapped: wrapped, identity: bob, context: 'space|s1|1|bob'),
          key);
      // Wrong person.
      await expectLater(
          KeyWrap.unwrap(
              wrapped: wrapped, identity: alice, context: 'space|s1|1|bob'),
          throwsA(anything));
      // Moved to another space or epoch by the server.
      await expectLater(
          KeyWrap.unwrap(
              wrapped: wrapped, identity: bob, context: 'space|s1|2|bob'),
          throwsA(anything));
      // Tampered.
      final bad = Uint8List.fromList(wrapped)..[40] ^= 1;
      await expectLater(
          KeyWrap.unwrap(
              wrapped: bad, identity: bob, context: 'space|s1|1|bob'),
          throwsA(anything));
    });

    test('uses a fresh ephemeral key every time', () async {
      final bob = await ZtIdentity.fromDek(bytes(12));
      final a = await KeyWrap.wrap(
          key: bytes(1), recipient: bob.public, context: 'c');
      final b = await KeyWrap.wrap(
          key: bytes(1), recipient: bob.public, context: 'c');
      expect(a.sublist(0, 32), isNot(b.sublist(0, 32)));
    });
  });

  group('InviteSecret', () {
    test('answers open only with the same token and invite id', () async {
      final secret = InviteSecret.generate();
      final sealed = await secret.sealAnswer('inv1', {'name': 'Grandma'});
      expect(await secret.openAnswer('inv1', sealed), {'name': 'Grandma'});
      await expectLater(secret.openAnswer('inv2', sealed), throwsA(anything));
      await expectLater(InviteSecret.generate().openAnswer('inv1', sealed),
          throwsA(anything));
    });

    test('hash is SHA-256 of the token', () async {
      final secret = InviteSecret(List.filled(32, 0));
      expect(
          (await secret.hash())
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
          '66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925');
    });
  });

  group('VerificationCode', () {
    test('both sides get the same 8 digits; a swapped key changes them',
        () async {
      final alice = await ZtIdentity.fromDek(bytes(20));
      final bob = await ZtIdentity.fromDek(bytes(21));
      final mallory = await ZtIdentity.fromDek(bytes(22));
      final a = await alice.public.fingerprint();
      final b = await bob.public.fingerprint();
      final code = await VerificationCode.compute(
          inviteId: 'i', inviterFingerprint: a, inviteeFingerprint: b);
      expect(code, matches(RegExp(r'^\d{4} \d{4}$')));
      expect(
          await VerificationCode.compute(
              inviteId: 'i', inviterFingerprint: a, inviteeFingerprint: b),
          code);
      expect(
          await VerificationCode.compute(
              inviteId: 'i',
              inviterFingerprint: a,
              inviteeFingerprint: await mallory.public.fingerprint()),
          isNot(code));
      expect(
          await VerificationCode.compute(
              inviteId: 'j', inviterFingerprint: a, inviteeFingerprint: b),
          isNot(code));
    });
  });
}
