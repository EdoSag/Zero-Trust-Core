import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

void main() {
  test('is off under flutter test, whose clock never fires its timer', () {
    expect(Breather().enabled, isFalse);
    expect(Breather(enabled: true).enabled, isTrue);
    expect(Breather(pause: () async {}).enabled, isTrue);
  });

  test('a loop pauses once a slice of work has passed', () async {
    var pauses = 0;
    final breather = Breather(slice: Duration.zero, pause: () async => pauses++)
      ..start();
    for (var i = 0; i < 5; i++) {
      await breather.step();
    }
    expect(pauses, 5);

    pauses = 0;
    final patient =
        Breather(slice: const Duration(hours: 1), pause: () async => pauses++)
          ..start();
    for (var i = 0; i < 5; i++) {
      await patient.step();
    }
    expect(pauses, 0, reason: 'the slice is not used up');
  });

  test('a few saves in a row are left alone, a long run is interrupted',
      () async {
    var pauses = 0;
    final breather =
        Breather(slice: Duration.zero, burst: 8, pause: () async => pauses++);
    for (var i = 0; i < 7; i++) {
      await breather.enter();
      breather.leave();
    }
    expect(pauses, 0);
    for (var i = 0; i < 20; i++) {
      await breather.enter();
      breather.leave();
    }
    expect(pauses, 20);
  });

  test('work after a quiet moment starts a new run', () async {
    var pauses = 0;
    final breather = Breather(
      slice: Duration.zero,
      idleGap: const Duration(milliseconds: 20),
      burst: 3,
      pause: () async => pauses++,
    );
    for (var round = 0; round < 3; round++) {
      await breather.enter();
      breather.leave();
      await breather.enter();
      breather.leave();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    expect(pauses, 0, reason: 'no run reached three');
  });

  group('the sync engine', () {
    late FakeSyncBackend server;
    late Uint8List appKey;
    late Ed25519KeyMaterial signing;
    final now = DateTime.utc(2026, 10, 11, 12);

    setUp(() async {
      server = FakeSyncBackend();
      appKey = await KeyHierarchy.appKey(
          Uint8List.fromList(List.generate(32, (i) => i)), 'notes');
      signing = await KeyHierarchy.signingKeys(appKey);
    });

    ItemSyncEngine device(String id, {Breather? breather}) => ItemSyncEngine(
          appId: 'notes',
          appKey: appKey,
          deviceId: id,
          store: InMemoryItemStore(),
          backend: server,
          signingKeys: signing,
          clock: () => now,
          breather: breather,
        );

    test('gives the screen a turn while an import saves and uploads', () async {
      var pauses = 0;
      final phone = device('phone',
          breather:
              Breather(slice: Duration.zero, pause: () async => pauses++));
      for (var i = 0; i < 100; i++) {
        await phone.save('n$i', {'v': i});
      }
      expect(pauses, greaterThan(80), reason: 'between the saves');

      pauses = 0;
      expect((await phone.sync()).pushed, 100);
      expect(pauses, greaterThanOrEqualTo(100), reason: 'between the rows');
      expect(server.rows, hasLength(100));
    });

    test('gives the screen a turn while a large pull is read', () async {
      final phone = device('phone');
      for (var i = 0; i < 60; i++) {
        await phone.save('n$i', {'v': i});
      }
      await phone.sync();

      var pauses = 0;
      final laptop = device('laptop',
          breather:
              Breather(slice: Duration.zero, pause: () async => pauses++));
      expect((await laptop.sync()).applied, 60);
      expect(pauses, greaterThanOrEqualTo(60));
      expect((await laptop.store.get('n59'))!.json, {'v': 59});
    });

    test('an edit made during a pause is not lost', () async {
      final phone = device('phone');
      for (var i = 0; i < 20; i++) {
        await phone.save('n$i', {'v': i});
      }
      await phone.sync();

      // The laptop edits n5 while its first pull is still being read.
      late ItemSyncEngine laptop;
      var edited = false;
      laptop = device('laptop',
          breather: Breather(
              slice: Duration.zero,
              pause: () async {
                if (edited) return;
                edited = true;
                await laptop.store.put(LocalItem(
                    itemId: 'n5',
                    updatedAt: now.add(const Duration(minutes: 1)),
                    json: {'v': 'mine'},
                    dirty: true));
              }));
      await laptop.sync();
      expect((await laptop.store.get('n5'))!.json, {'v': 'mine'});
      expect((await laptop.store.get('n6'))!.json, {'v': 6});
    });

    test('with real pauses and the real store an import goes up and arrives',
        () async {
      final store = await ZtLocalStore.open(appKey: appKey, mergeBursts: true);
      addTearDown(store.close);
      final announced = <String>{};
      var events = 0;
      store.changes.listen((ids) {
        events++;
        announced.addAll(ids);
      });
      final phone = ItemSyncEngine(
        appId: 'notes',
        appKey: appKey,
        deviceId: 'phone',
        store: store,
        backend: server,
        signingKeys: signing,
        clock: () => now,
        breather: Breather(enabled: true),
      );
      for (var i = 0; i < 300; i++) {
        await phone.save('n$i', {'v': i});
      }
      expect((await phone.sync()).pushed, 300);
      expect((await store.dirtyItems()), isEmpty);

      final laptop = device('laptop', breather: Breather(enabled: true));
      expect((await laptop.sync()).applied, 300);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(announced, hasLength(300));
      expect(events, lessThan(300), reason: 'announced in batches');
    });
  });
}
