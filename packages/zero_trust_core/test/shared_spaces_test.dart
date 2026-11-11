import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';
const carol = '00000000-0000-4000-8000-00000000000c';
const mallory = '00000000-0000-4000-8000-0000000000ff';

Uint8List dek(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 7 + i) & 0xff));

/// One account on one device.
class Device {
  Device(this.server, this.userId, int seed,
      {String device = 'd', this.policy = defaultPolicy})
      : _seed = seed,
        _device = '$device-$userId';

  static const defaultPolicy =
      SpacePolicy(adminOnlyKinds: {'medication'}, ownedPrefixes: {'progress/'});
  final SpacePolicy policy;

  final InMemorySpaceServer server;
  final String userId;
  final int _seed;
  final String _device;
  final private = InMemorySpaceStore();
  final Map<String, InMemoryItemStore> stores = {};
  late final SharedSpaces spaces;

  Future<Device> start({InMemorySpaceStore? sharedPrivate}) async {
    spaces = SharedSpaces(
      app: 'meds',
      myUserId: userId,
      identity: await ZtIdentity.fromDek(dek(_seed)),
      backend: server.backendFor(userId),
      privateStore: sharedPrivate ?? private,
      openStore: (id) async => stores.putIfAbsent(id, InMemoryItemStore.new),
      deleteStore: (id) async => stores.remove(id),
      deviceId: _device,
      policy: policy,
    );
    return this;
  }

  Future<Map<String, Object?>?> read(String spaceId, String itemId) async =>
      (await stores[spaceId]?.get(itemId))?.json;
}

class InMemorySpaceStore extends InMemorySpacePrivateStore {}

/// Alice creates a space and lets [who] in as [role]; returns the space id.
Future<String> share(Device admin, Device who,
    {SpaceRole role = SpaceRole.member, String name = 'Bob'}) async {
  final spaces = await admin.spaces.list();
  final String spaceId;
  if (spaces.isEmpty) {
    spaceId = (await admin.spaces.create(myName: 'Alice')).id;
  } else {
    spaceId = spaces.first.id;
  }
  final link = await admin.spaces.invite(spaceId, role: role);
  final parsed = SpaceInviteLink.parse(link.toString());
  final joined = await who.spaces.answer(parsed, myName: name);
  final pending = await admin.spaces.pendingJoins(spaceId);
  expect(pending.single.verificationCode, joined.verificationCode);
  await admin.spaces.confirm(pending.single);
  await who.spaces.sync(await who.spaces.open(spaceId));
  return spaceId;
}

void main() {
  late InMemorySpaceServer server;
  late Device a, b, c, x;

  setUp(() async {
    server = InMemorySpaceServer();
    a = await Device(server, alice, 1).start();
    b = await Device(server, bob, 2).start();
    c = await Device(server, carol, 3).start();
    x = await Device(server, mallory, 9).start();
  });

  group('invites', () {
    test('link round-trips, and junk is refused', () async {
      final space = await a.spaces.create(myName: 'Alice');
      final link = await a.spaces.invite(space.id);
      final text = link.toString();
      expect(text, startsWith('https://zerotrust.bz/join#zt1.meds.'));
      final back = SpaceInviteLink.parse(text);
      expect(back.inviteId, link.inviteId);
      expect(back.secret.token, link.secret.token);
      expect(back.inviterFingerprint, link.inviterFingerprint);
      expect(
          SpaceInviteLink.parse(text.split('#').last).inviteId, link.inviteId);
      expect(link.qrData, text);
      for (final bad in ['', 'https://zerotrust.bz/join', 'zt1.meds.x.y.z.w']) {
        expect(() => SpaceInviteLink.parse(bad), throwsFormatException);
      }
    });

    test('both phones show the same code; the joiner reads the space',
        () async {
      final space = await a.spaces.create(myName: 'Alice');
      await space.save('child', {'kind': 'child', 'name': 'Noa'});
      await a.spaces.sync(space);

      final spaceId = await share(a, b);
      expect(await b.read(spaceId, 'child'), containsPair('name', 'Noa'));
      final bs = await b.spaces.open(spaceId);
      expect({for (final m in bs.members) m.userId: m.name},
          {alice: 'Alice', bob: 'Bob'});
      expect(bs.isAdmin, isFalse);
    });

    test('a stolen link answered first shows a different code', () async {
      final space = await a.spaces.create(myName: 'Alice');
      final link = await a.spaces.invite(space.id);
      // Mallory intercepted the message and answers first.
      final m =
          await x.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
      // Bob can't use it any more.
      await expectLater(
          b.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob'),
          throwsA(isA<SpaceRefused>()));
      // Alice sees "Bob" waiting, but the code isn't the one on Bob's phone
      // (Bob has none); it is Mallory's, made with Mallory's key.
      final pending = (await a.spaces.pendingJoins(space.id)).single;
      expect(pending.userId, mallory);
      expect(pending.verificationCode, m.verificationCode);
      final bobsCode = await VerificationCode.compute(
        inviteId: link.inviteId,
        inviterFingerprint: link.inviterFingerprint,
        inviteeFingerprint:
            await (await ZtIdentity.fromDek(dek(2))).public.fingerprint(),
      );
      expect(pending.verificationCode, isNot(bobsCode));
      await a.spaces.revokeInvite(pending.inviteId);
      expect(await a.spaces.pendingJoins(space.id), isEmpty);
    });

    test('a server that swaps the answer is caught: it no longer opens',
        () async {
      final space = await a.spaces.create(myName: 'Alice');
      final link = await a.spaces.invite(space.id);
      await b.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
      // The server can't seal a valid answer without the token, so a
      // replaced answer (another key in Bob's name) is left out entirely.
      final forged = await InviteSecret.generate().sealAnswer(link.inviteId, {
        'userId': bob,
        'name': 'Bob',
        'identity': (await ZtIdentity.fromDek(dek(9))).public.toJson(),
      });
      expect(await a.spaces.pendingJoins(space.id), hasLength(1));
      server.replaceAnswer(link.inviteId, forged);
      expect(await a.spaces.pendingJoins(space.id), isEmpty);
    });

    test('only admins invite; invites are single use', () async {
      final spaceId = await share(a, b);
      await expectLater(b.spaces.invite(spaceId), throwsA(isA<SpaceRefused>()));
      final link = await a.spaces.invite(spaceId);
      await c.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Carol');
      await expectLater(
          x.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'X'),
          throwsA(isA<SpaceRefused>()));
    });
  });

  group('trust', () {
    test('a key planted by the server is never used for writing', () async {
      final space = await a.spaces.create(myName: 'Alice');
      final link = await a.spaces.invite(space.id);
      await b.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
      final join = (await a.spaces.pendingJoins(space.id)).single;
      await a.spaces.confirm(join);

      // The server rotates on its own, wrapping a key it knows for Bob.
      final evil = await ZtIdentity.fromDek(dek(66));
      final known = Uint8List(32);
      final wrapped = await KeyWrap.wrap(
          key: known,
          recipient: (await ZtIdentity.fromDek(dek(2))).public,
          context: spaceKeyContext(space.id, 1, bob));
      server.plantKey(
          space.id,
          bob,
          SpaceKeyGrant(
              userId: bob,
              epoch: 1,
              wrappedKey: wrapped,
              signature: await evil.sign([1])),
          wrappedBy: mallory);

      final bs = await b.spaces.open(space.id);
      await b.spaces.sync(bs);
      // Nothing opened, so Bob's phone refuses to seal anything.
      expect(bs.codec.keyring.writeEpoch, isNull);
      await bs.save('dose1', {'kind': 'dose'});
      await expectLater(bs.engine.sync(), throwsA(isA<SpaceKeyUnavailable>()));
      expect(
          server.rowsOf(space.id).where((r) => r.itemId == 'dose1'), isEmpty);
    });

    test('a planted key is replaced, not confirmed, by the real signed row',
        () async {
      final space = await a.spaces.create(myName: 'Alice');
      final link = await a.spaces.invite(space.id);
      await b.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
      await a.spaces.confirm((await a.spaces.pendingJoins(space.id)).single);
      final real = (await server.backendFor(bob).myKeys(space.id)).single;

      // First the server hands Bob a key it knows, badly signed...
      final known = Uint8List(32);
      server.plantKey(
          space.id,
          bob,
          SpaceKeyGrant(
              userId: bob,
              epoch: 1,
              wrappedKey: await KeyWrap.wrap(
                  key: known,
                  recipient: (await ZtIdentity.fromDek(dek(2))).public,
                  context: spaceKeyContext(space.id, 1, bob)),
              signature: Uint8List(64)),
          wrappedBy: alice);
      final bs = await b.spaces.open(space.id);
      await b.spaces.sync(bs);
      expect(bs.codec.keyring.writeEpoch, isNull);

      // ...then the real row, signed by Alice.
      server.plantKey(
          space.id,
          bob,
          SpaceKeyGrant(
              userId: bob,
              epoch: 1,
              wrappedKey: real.wrappedKey,
              signature: real.signature),
          wrappedBy: real.wrappedBy);
      await b.spaces.sync(bs);
      expect(bs.codec.keyring.writeEpoch, 1);
      final as = await a.spaces.open(space.id);
      expect(bs.codec.keyring[1], as.codec.keyring[1]);
      expect(bs.codec.keyring[1], isNot(known));
    });

    test('someone invited by a second admin trusts the whole space', () async {
      final spaceId = await share(a, b, role: SpaceRole.admin);
      final as = await a.spaces.open(spaceId);
      await as.save('med', {'kind': 'medication', 'name': 'Amoxicillin'});
      await a.spaces.sync(as);

      // Bob (admitted by Alice) invites Carol.
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      final link = await b.spaces.invite(spaceId);
      final started = await c.spaces
          .answer(SpaceInviteLink.parse('$link'), myName: 'Carol');
      final join = (await b.spaces.pendingJoins(spaceId)).single;
      expect(join.verificationCode, started.verificationCode);
      await b.spaces.confirm(join);

      final cs = await c.spaces.open(spaceId);
      await c.spaces.sync(cs);
      expect(cs.roster[alice], isNotNull);
      expect(cs.roster[bob], isNotNull);
      expect(cs.codec.keyring.writeEpoch, 1);
      expect(await c.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));
      // And what Alice writes next reaches her too.
      await as.save('med2', {'kind': 'medication', 'name': 'Paracetamol'});
      await a.spaces.sync(as);
      await c.spaces.sync(cs);
      expect(
          await c.read(spaceId, 'med2'), containsPair('name', 'Paracetamol'));
    });

    test('rows the server forges or alters are rejected', () async {
      final spaceId = await share(a, b);
      final as = await a.spaces.open(spaceId);
      await as.save('note', {'kind': 'note', 'text': 'real'});
      await a.spaces.sync(as);

      final real = server.rowsOf(spaceId).firstWhere((r) => r.itemId == 'note');
      server.tamper(
          spaceId,
          RemoteItem(
            itemId: 'note',
            updatedAt: real.updatedAt.add(const Duration(seconds: 1)),
            deviceId: 'srv',
            dataBlob: real.dataBlob,
            signature: real.signature,
            keyEpoch: real.keyEpoch,
            authorId: real.authorId,
            syncedAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ));
      final bs = await b.spaces.open(spaceId);
      final result = await b.spaces.sync(bs);
      expect(result.rejected, contains('note'));
      expect(await b.read(spaceId, 'note'), isNull);
    });

    test("a member's admin-only row is refused even if the server lets it in",
        () async {
      final spaceId = await share(a, b);
      final bs = await b.spaces.open(spaceId);
      await bs.save('med', {'kind': 'medication', 'name': 'Bad'});
      await expectLater(b.spaces.sync(bs), throwsA(isA<SpaceRefused>()));

      server.enforceAdminOnly = false;
      await b.spaces.sync(bs);
      final as = await a.spaces.open(spaceId);
      final result = await a.spaces.sync(as);
      expect(result.rejected, contains('med'));
      expect(await a.read(spaceId, 'med'), isNull);
    });

    test("items owned by one member can't be written in their name", () async {
      final spaceId = await share(a, b);
      final bs = await b.spaces.open(spaceId);
      await bs.save('progress/$bob', {'kind': 'progress', 'total': 10});
      await b.spaces.sync(bs);
      expect(() => bs.save('progress/$alice', {'kind': 'progress'}),
          throwsArgumentError);
      // Not even an admin may write or delete another member's item.
      final as = await a.spaces.open(spaceId);
      expect(() => as.delete('progress/$bob'), throwsArgumentError);
      await a.spaces.sync(as);
      expect((await a.read(spaceId, 'progress/$bob'))?['total'], 10);

      // A changed app that skips the check: the others refuse its rows.
      final evil = await Device(server, bob, 2,
              device: 'evil', policy: const SpacePolicy())
          .start(sharedPrivate: b.private);
      final es = await evil.spaces.open(spaceId);
      await evil.spaces.sync(es);
      await es.save('progress/$alice', {'kind': 'progress', 'total': 1});
      await es.save('progress/$bob/2026-11-11', {'kind': 'progress'});
      await evil.spaces.sync(es);
      final result = await a.spaces.sync(as);
      expect(result.rejected, contains('progress/$alice'));
      expect(await a.read(spaceId, 'progress/$alice'), isNull);
      expect(await a.read(spaceId, 'progress/$bob/2026-11-11'), isNotNull);
    });

    test('a member list entry not written by an admin is ignored', () async {
      final spaceId = await share(a, b);
      server.enforceAdminOnly = false;
      final bs = await b.spaces.open(spaceId);
      final fake = SpaceMember(
        userId: mallory,
        name: 'Grandma',
        identity: (await ZtIdentity.fromDek(dek(9))).public,
        role: SpaceRole.admin,
      );
      await bs.save(SpaceMember.itemIdFor(mallory, by: bob), fake.toJson());
      await b.spaces.sync(bs);
      final as = await a.spaces.open(spaceId);
      await a.spaces.sync(as);
      expect(as.roster[mallory], isNull);
    });
  });

  group('removal and rotation', () {
    test('removing a member rotates the key; they lose the space', () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      final as = await a.spaces.open(spaceId);
      expect(as.keyEpoch, 1);

      await a.spaces.remove(spaceId, carol);
      expect(as.keyEpoch, 2);
      expect(as.roster[carol]!.removedAtEpoch, 2);

      await as.save('dose', {'kind': 'dose', 'note': 'after Carol left'});
      await a.spaces.sync(as);
      final row = server.rowsOf(spaceId).firstWhere((r) => r.itemId == 'dose');
      expect(row.keyEpoch, 2);

      // Bob moves to the new key and reads it.
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      expect(bs.keyEpoch, 2);
      expect(await b.read(spaceId, 'dose'),
          containsPair('note', 'after Carol left'));

      // Carol's phone notices and wipes its copy.
      final cs = await c.spaces.open(spaceId);
      await c.spaces.sync(cs);
      expect(cs.gone, isTrue);
      expect(c.stores, isNot(contains(spaceId)));
      // The old key doesn't open the new row.
      final oldKey = await KeyWrap.unwrap(
        wrapped: (await server.backendFor(bob).myKeys(spaceId))
            .firstWhere((k) => k.epoch == 1)
            .wrappedKey,
        identity: await ZtIdentity.fromDek(dek(2)),
        context: spaceKeyContext(spaceId, 1, bob),
      );
      await expectLater(
          SealedBox.open(row.dataBlob!, oldKey,
              aad: utf8.encode('zt/space-item/v1|$spaceId|dose|2')),
          throwsA(anything));
    });

    test(
        'a removed member can no longer write, and later rows from them '
        'are refused', () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      await a.spaces.remove(spaceId, carol);
      expect(() => server.backendFor(carol).items(spaceId).pull('meds'),
          throwsA(isA<SpaceRefused>()));
    });

    test('when someone leaves, the next admin sync makes a new key', () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      await c.spaces.leave(spaceId);
      expect(c.stores, isNot(contains(spaceId)));
      expect((await a.spaces.list()).single.rotationNeeded, isTrue);

      final as = await a.spaces.open(spaceId);
      await a.spaces.sync(as);
      expect(as.keyEpoch, 2);
      expect((await a.spaces.list()).single.rotationNeeded, isFalse);
      expect(as.roster[carol]!.removed, isTrue);

      final bs = await b.spaces.open(spaceId);
      await bs.save('dose', {'kind': 'dose'});
      await b.spaces.sync(bs);
      expect(
          server.rowsOf(spaceId).firstWhere((r) => r.itemId == 'dose').keyEpoch,
          2);
    });

    test('edits waiting on the admin\'s phone go out under the new key',
        () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      await c.spaces.leave(spaceId);
      // Alice edited offline before learning Carol left.
      final as = await a.spaces.open(spaceId);
      await as.save('dose', {'kind': 'dose', 'note': 'after Carol left'});
      await a.spaces.sync(as);
      expect(as.keyEpoch, 2);
      expect(
          server.rowsOf(spaceId).firstWhere((r) => r.itemId == 'dose').keyEpoch,
          2);
    });

    test('the last admin leaving promotes the longest-standing member',
        () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      await a.spaces.leave(spaceId);
      final info = (await b.spaces.list()).single;
      expect(info.myRole, SpaceRole.admin);
      // Bob's phone rotates (he is admin now and Alice left).
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      expect(bs.keyEpoch, 2);
      final cs = await c.spaces.open(spaceId);
      await cs.save('dose', {'kind': 'dose'});
      await c.spaces.sync(cs);
      await b.spaces.sync(bs);
      expect(await b.read(spaceId, 'dose'), isNotNull);
    });

    test(
        "a member's write sealed under the old key is retried with the new one",
        () async {
      final spaceId = await share(a, b);
      await share(a, c, name: 'Carol');
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      // Bob logs offline while Alice removes Carol.
      await bs.save('dose', {'kind': 'dose', 'by': 'Bob'});
      await a.spaces.remove(spaceId, carol);
      await b.spaces.sync(bs);
      final row = server.rowsOf(spaceId).firstWhere((r) => r.itemId == 'dose');
      expect(row.keyEpoch, 2);
    });

    test('roles: promote, and never without an admin', () async {
      final spaceId = await share(a, b);
      await a.spaces.setRole(spaceId, bob, SpaceRole.admin);
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      expect(bs.isAdmin, isTrue);
      expect(bs.roster[bob]!.role, SpaceRole.admin);
      // Bob can now invite.
      await b.spaces.invite(spaceId);
      await a.spaces.setRole(spaceId, alice, SpaceRole.member);
      await expectLater(b.spaces.setRole(spaceId, bob, SpaceRole.member),
          throwsA(isA<SpaceRefused>()));
    });

    test('deleting the space removes it for everyone', () async {
      final spaceId = await share(a, b);
      await expectLater(
          b.spaces.deleteSpace(spaceId), throwsA(isA<SpaceRefused>()));
      await a.spaces.deleteSpace(spaceId);
      expect(server.hasSpace(spaceId), isFalse);
      final bs = await b.spaces.open(spaceId);
      await b.spaces.sync(bs);
      expect(bs.gone, isTrue);
    });
  });

  test(
      "a second device of the joiner trusts the space through the account's "
      'private notes', () async {
    final spaceId = await share(a, b);
    final b2 = await Device(server, bob, 2, device: 'tablet')
        .start(sharedPrivate: b.private);
    final s2 = await b2.spaces.open(spaceId);
    await b2.spaces.sync(s2);
    expect(s2.roster[alice]!.name, 'Alice');
    expect(s2.codec.keyring.writeEpoch, 1);
  });

  test('fresh devices still trust the space after a second admin confirms',
      () async {
    final spaceId = await share(a, b, role: SpaceRole.admin);
    final as = await a.spaces.open(spaceId);
    await as.save('med', {'kind': 'medication', 'name': 'Amoxicillin'});
    await a.spaces.sync(as);
    final bs = await b.spaces.open(spaceId);
    await b.spaces.sync(bs);
    final link = await b.spaces.invite(spaceId);
    await c.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Carol');
    await b.spaces.confirm((await b.spaces.pendingJoins(spaceId)).single);
    // Another admin changing the creator's entry must not break it either.
    await b.spaces.rename(spaceId, alice, 'Mom');

    final a2 = await Device(server, alice, 1, device: 'tablet')
        .start(sharedPrivate: a.private);
    final s2 = await a2.spaces.open(spaceId);
    await a2.spaces.sync(s2);
    expect(s2.roster[alice], isNotNull, reason: 'alice fresh device');
    expect(s2.roster[alice]!.name, 'Mom');
    expect(s2.roster[carol], isNotNull);
    expect(await a2.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));
    final b2 = await Device(server, bob, 2, device: 'tablet')
        .start(sharedPrivate: b.private);
    final t2 = await b2.spaces.open(spaceId);
    await b2.spaces.sync(t2);
    expect(t2.roster[bob], isNotNull, reason: 'bob fresh device');
    expect(await b2.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));
    final c2 = await Device(server, carol, 3, device: 'tablet')
        .start(sharedPrivate: c.private);
    final u2 = await c2.spaces.open(spaceId);
    await c2.spaces.sync(u2);
    expect(u2.roster[alice]?.name, 'Mom', reason: 'carol fresh device');
    expect(await c2.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));
  });

  test('an admin cannot write the member list rows of another admin', () async {
    final spaceId = await share(a, b, role: SpaceRole.admin);
    final bs = await b.spaces.open(spaceId);
    await b.spaces.sync(bs);
    final fake = bs.roster[alice]!.copyWith(name: 'Not Alice');
    await bs.save(SpaceMember.itemIdFor(alice, by: alice), fake.toJson());
    await b.spaces.sync(bs);
    final as = await a.spaces.open(spaceId);
    final result = await a.spaces.sync(as);
    expect(result.rejected, contains(SpaceMember.itemIdFor(alice, by: alice)));
    expect(as.roster[alice]!.name, 'Alice');
  });

  test('spaces from before per-admin rows are repaired by an admin device',
      () async {
    final spaceId = await share(a, b, role: SpaceRole.admin);
    final as = await a.spaces.open(spaceId);
    await as.save('med', {'kind': 'medication', 'name': 'Amoxicillin'});
    await a.spaces.sync(as);
    final bs = await b.spaces.open(spaceId);
    await b.spaces.sync(bs);
    // The old layout after Bob confirmed someone: one shared row per
    // member, every one rewritten under Bob's signature.
    for (final m in bs.roster.all.toList()) {
      await bs.engine.save(SpaceMember.legacyItemIdFor(m.userId), m.toJson());
    }
    await bs.engine.sync();
    for (final who in [alice, bob]) {
      await as.engine.delete(SpaceMember.itemIdFor(who, by: alice));
      await bs.engine.delete(SpaceMember.itemIdFor(who, by: bob));
    }
    await as.engine.sync();
    await bs.engine.sync();

    // Bob's new phone trusts the space through his own (legacy) entry.
    final b2 = await Device(server, bob, 2, device: 'tablet')
        .start(sharedPrivate: b.private);
    final t2 = await b2.spaces.open(spaceId);
    await b2.spaces.sync(t2);
    expect(t2.roster[alice], isNotNull);
    expect(await b2.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));

    // Alice's new phone has nothing she signed to start from...
    final a3 = await Device(server, alice, 1, device: 'old-tablet')
        .start(sharedPrivate: a.private);
    final s3 = await a3.spaces.open(spaceId);
    await a3.spaces.sync(s3);
    expect(s3.roster[alice], isNull);
    // ...until her old phone syncs once and vouches again in her own rows.
    await a.spaces.sync(as);
    final a2 = await Device(server, alice, 1, device: 'tablet')
        .start(sharedPrivate: a.private);
    final s2 = await a2.spaces.open(spaceId);
    await a2.spaces.sync(s2);
    expect(s2.roster[bob], isNotNull);
    expect(await a2.read(spaceId, 'med'), containsPair('name', 'Amoxicillin'));
  });

  test('without the private note a device refuses to trust the space',
      () async {
    final spaceId = await share(a, b);
    final stranger = await Device(server, bob, 2, device: 'new').start();
    await expectLater(
        stranger.spaces.open(spaceId), throwsA(isA<SpaceNotTrusted>()));
  });
}
