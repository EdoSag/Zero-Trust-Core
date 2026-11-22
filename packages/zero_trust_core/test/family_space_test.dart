import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';

Uint8List dek(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 7 + i) & 0xff));

/// One app of one account on one phone, looking at the family circles.
class App {
  App(this.server, this.userId, this.seed, this.appId, this.suiteServer);

  final InMemorySpaceServer server;
  final String userId;
  final int seed;
  final String appId;

  /// The account's `vault_items` (its suite notes live there).
  final FakeSyncBackend? suiteServer;

  /// The app's own synced notes.
  final own = InMemorySpacePrivateStore();
  final Map<String, InMemoryItemStore> stores = {};
  late final SharedSpaces spaces;

  Future<App> start({bool familyStore = true}) async {
    final suite = suiteServer == null
        ? null
        : await ZtSuiteNotes.open(
            suiteKey: await KeyHierarchy.appKey(dek(seed), ztSuiteNotesApp),
            backend: suiteServer!,
            deviceId: 'phone-$userId',
          );
    spaces = SharedSpaces(
      app: ZtFamilySpace.app,
      myUserId: userId,
      identity: await ZtIdentity.fromDek(dek(seed)),
      backend: server.backendFor(userId),
      privateStore: familyStore
          ? ZtFamilyPrivateStore(
              own: own, suite: suite, publish: appId == ZtFamilySpace.app)
          : own,
      openStore: (id) async => stores.putIfAbsent(id, InMemoryItemStore.new),
      deleteStore: (id) async => stores.remove(id),
      deviceId: '$appId-$userId',
      policy: ZtFamilySpace.policy,
    );
    return this;
  }

  Future<Map<String, Object?>?> read(String spaceId, String itemId) async =>
      (await stores[spaceId]?.get(itemId))?.json;
}

/// [admin] makes a circle and lets [who] in; returns its id.
Future<String> circle(App admin, App who) async {
  final spaceId = (await admin.spaces.create(myName: 'Alice')).id;
  final link = await admin.spaces.invite(spaceId);
  await who.spaces.answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
  await admin.spaces.confirm((await admin.spaces.pendingJoins(spaceId)).single);
  await who.spaces.sync(await who.spaces.open(spaceId));
  return spaceId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('item ids', () {
    test('apps write <app>/<kind>/<id>; the rest is ZT Family\'s', () {
      expect(
          ZtFamilySpace.itemId('calendar', 'event', 'e1'), 'calendar/event/e1');
      expect(ZtFamilySpace.appOf('calendar/event/e1'), 'calendar');
      expect(ZtFamilySpace.appOf('tasks/item/x/y'), 'tasks');
      expect(ZtFamilySpace.belongsTo('meds/dose/9', 'meds'), isTrue);
      expect(ZtFamilySpace.belongsTo('meds/dose/9', 'tasks'), isFalse);
      for (final own in [
        'family.circle',
        'family.place/p1',
        'family.me/$alice/phone',
        'family.pending-joins',
        'zt.member/$alice',
        'family/event/1',
        'calendar/',
        'calendar/event/',
      ]) {
        expect(ZtFamilySpace.appOf(own), isNull, reason: own);
      }
      for (final bad in [
        ['Calendar', 'event', '1'],
        ['family', 'event', '1'],
        ['calendar', 'Event', '1'],
        ['calendar', 'event', ''],
        ['calendar', 'event', 'x' * 200],
      ]) {
        expect(() => ZtFamilySpace.itemId(bad[0], bad[1], bad[2]),
            throwsArgumentError,
            reason: '$bad');
      }
    });

    test('summaries round-trip and junk is ignored', () {
      final at = DateTime.utc(2026, 11, 23, 17);
      final json = ZtFamilySummary(
        title: 'Dentist',
        kind: 'calendar.event',
        at: at,
        list: 'calendar/calendar/home',
      ).addTo({'kind': 'calendar.event', 'notes': 'bring the card'});
      expect(json['notes'], 'bring the card');
      final back = ZtFamilySummary.of(json)!;
      expect(back.title, 'Dentist');
      expect(back.kind, 'calendar.event');
      expect(back.at, at);
      expect(back.due, isNull);
      expect(back.done, isNull);
      expect(back.list, 'calendar/calendar/home');
      expect(ZtFamilySummary.of({'kind': 'x'}), isNull);
      expect(ZtFamilySummary.of({'zt': 'text'}), isNull);
      expect(
          ZtFamilySummary.of({
            'zt': {'t': 1, 'kind': 'x'}
          }),
          isNull);
    });

    test('one rule for the circle, the same as ZT Family\'s', () {
      expect(ZtFamilySpace.policy.adminOnlyKinds, {'family.circle'});
      expect(ZtFamilySpace.policy.ownedPrefixes, {'family.me/'});
    });
  });

  test('every app derives the same suite key, zeroed on lock', () async {
    Future<(Uint8List, VaultController)> unlock(String appId) async {
      final c = ProviderContainer(overrides: [
        ztAppConfigProvider.overrideWithValue(
            ZtAppConfig(appId: appId, displayName: 'Zero-Trust $appId')),
        ztPreferencesStoreProvider
            .overrideWithValue(InMemoryPreferencesStore()),
      ]);
      addTearDown(c.dispose);
      final vault = c.read(vaultControllerProvider.notifier);
      await vault.unlock(dek(1));
      final key = (c.read(vaultControllerProvider) as VaultUnlocked).suiteKey!;
      return (key, vault);
    }

    final (familyKey, _) = await unlock('family');
    final (calendarKey, calendarVault) = await unlock('calendar');
    expect(calendarKey, familyKey);
    expect(calendarKey, await KeyHierarchy.appKey(dek(1), ztSuiteNotesApp));
    expect(calendarKey, isNot(await KeyHierarchy.appKey(dek(1), 'calendar')));
    calendarVault.lock();
    expect(calendarKey.every((b) => b == 0), isTrue);
  });

  group('every app opens the family circle', () {
    late InMemorySpaceServer server;
    late FakeSyncBackend aliceVault, bobVault;

    setUp(() {
      server = InMemorySpaceServer();
      aliceVault = FakeSyncBackend()..guardFuture = false;
      bobVault = FakeSyncBackend()..guardFuture = false;
    });

    test(
        "Calendar opens the circle ZT Family made, and Family's hub reads "
        'its items', () async {
      final family = await App(server, alice, 1, 'family', aliceVault).start();
      final bobFamily = await App(server, bob, 2, 'family', bobVault).start();
      final spaceId = await circle(family, bobFamily);

      // Alice's Calendar never joined anything itself.
      final calendar =
          await App(server, alice, 1, 'calendar', aliceVault).start();
      expect(await calendar.own.read(SharedSpaces.anchorId(spaceId)), isNull);
      expect((await calendar.spaces.list()).single.id, spaceId);
      final cal = await calendar.spaces.open(spaceId);
      await calendar.spaces.sync(cal);
      expect({for (final m in cal.members) m.userId}, {alice, bob});
      // It keeps its own copy now, so it opens offline next time.
      expect(
          await calendar.own.read(SharedSpaces.anchorId(spaceId)), isNotNull);

      final id = ZtFamilySpace.itemId('calendar', 'event', 'e1');
      await cal.save(
          id,
          ZtFamilySummary(
                  title: 'Dentist',
                  kind: 'calendar.event',
                  at: DateTime.utc(2026, 11, 23, 17))
              .addTo({'kind': 'calendar.event', 'start': '2026-11-23T17:00Z'}));
      await calendar.spaces.sync(cal);

      // Bob's ZT Family sees it, with its summary and author.
      await bobFamily.spaces.sync(await bobFamily.spaces.open(spaceId));
      final seen = await bobFamily.read(spaceId, id);
      expect(ZtFamilySummary.of(seen)!.title, 'Dentist');
      expect(ZtFamilySpace.appOf(id), 'calendar');

      // And Bob's own Tasks can open the same circle.
      final bobTasks = await App(server, bob, 2, 'tasks', bobVault).start();
      final bt = await bobTasks.spaces.open(spaceId);
      await bobTasks.spaces.sync(bt);
      expect(ZtFamilySummary.of(await bobTasks.read(spaceId, id))!.kind,
          'calendar.event');
    });

    test('circles made before S-10 reach the other apps once ZT Family runs',
        () async {
      // An older ZT Family kept its notes only in its own store.
      final older = await App(server, alice, 1, 'family', aliceVault)
          .start(familyStore: false);
      final spaceId = (await older.spaces.create(myName: 'Alice')).id;
      final calendar =
          await App(server, alice, 1, 'calendar', aliceVault).start();
      await expectLater(
          calendar.spaces.open(spaceId), throwsA(isA<SpaceNotTrusted>()));

      // The new ZT Family, with the same synced notes, copies them up.
      final family = await App(server, alice, 1, 'family', aliceVault).start();
      family.own.items.addAll(older.own.items);
      await family.spaces.open(spaceId);
      await pumpEventQueue();

      final later = await App(server, alice, 1, 'calendar', aliceVault).start();
      expect((await later.spaces.open(spaceId)).id, spaceId);
    });

    test("another account's notes are no use, and forged ones are refused",
        () async {
      final family = await App(server, alice, 1, 'family', aliceVault).start();
      final bobFamily = await App(server, bob, 2, 'family', bobVault).start();
      final spaceId = await circle(family, bobFamily);

      // Bob's Calendar reading Alice's vault (a server mix-up) can't open
      // her notes: they're sealed under her suite key.
      final wrong = await App(server, bob, 2, 'calendar', aliceVault).start();
      await expectLater(
          wrong.spaces.open(spaceId), throwsA(isA<SpaceNotTrusted>()));

      // The server swaps Alice's row into Bob's vault: Bob's apps can't
      // open or check it, so they don't trust it.
      final anchor = SharedSpaces.anchorId(spaceId);
      bobVault.rows['$ztSuiteNotesApp/$anchor'] =
          aliceVault.rows['$ztSuiteNotesApp/$anchor']!;
      final bobCalendar =
          await App(server, bob, 2, 'calendar', bobVault).start();
      await expectLater(
          bobCalendar.spaces.open(spaceId), throwsA(isA<SpaceNotTrusted>()));

      // Bob's ZT Family puts his own back the next time it opens the circle.
      final bobFamilyAgain =
          await App(server, bob, 2, 'family', bobVault).start();
      bobFamilyAgain.own.items.addAll(bobFamily.own.items);
      await bobFamilyAgain.spaces.open(spaceId);
      await pumpEventQueue();
      final healed = await App(server, bob, 2, 'calendar', bobVault).start();
      expect((await healed.spaces.open(spaceId)).id, spaceId);
    });

    test('a member writing an admin-only item is refused in every app',
        () async {
      final family = await App(server, alice, 1, 'family', aliceVault).start();
      final bobFamily = await App(server, bob, 2, 'family', bobVault).start();
      final spaceId = await circle(family, bobFamily);
      final bs = await bobFamily.spaces.open(spaceId);
      await bs.save('family.circle', {'kind': 'family.circle', 'name': 'X'});
      server.enforceAdminOnly = false;
      await bobFamily.spaces.sync(bs);

      final calendar =
          await App(server, alice, 1, 'calendar', aliceVault).start();
      final result =
          await calendar.spaces.sync(await calendar.spaces.open(spaceId));
      expect(result.rejected, contains('family.circle'));
    });

    test('offline, the app still opens a circle it opened before', () async {
      final family = await App(server, alice, 1, 'family', aliceVault).start();
      final spaceId = (await family.spaces.create(myName: 'Alice')).id;
      final calendar =
          await App(server, alice, 1, 'calendar', aliceVault).start();
      await calendar.spaces.open(spaceId);

      aliceVault.rows.clear(); // stands in for "can't reach the server"
      final again = await App(server, alice, 1, 'calendar', aliceVault).start();
      again.own.items.addAll(calendar.own.items);
      expect((await again.spaces.open(spaceId)).id, spaceId);
    });
  });
}
