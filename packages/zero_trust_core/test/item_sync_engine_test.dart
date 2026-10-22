import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

void main() {
  late FakeSyncBackend server;
  late Uint8List appKey;
  late Ed25519KeyMaterial signing;
  var now = DateTime.utc(2026, 10, 11, 12);

  Future<ItemSyncEngine> device(String id, {Uint8List? key}) async =>
      ItemSyncEngine(
        appId: 'notes',
        appKey: key ?? appKey,
        deviceId: id,
        store: InMemoryItemStore(),
        backend: server,
        signingKeys:
            key == null ? signing : await KeyHierarchy.signingKeys(key),
        clock: () => now,
      );

  setUp(() async {
    server = FakeSyncBackend();
    final dek = Uint8List.fromList(List.generate(32, (i) => i));
    appKey = await KeyHierarchy.appKey(dek, 'notes');
    signing = await KeyHierarchy.signingKeys(appKey);
    now = DateTime.utc(2026, 10, 11, 12);
  });

  test('an item saved on one device arrives on another, encrypted at rest',
      () async {
    final phone = await device('phone');
    final laptop = await device('laptop');

    await phone.save('n1', {'title': 'Groceries', 'body': 'milk'});
    final pushed = await phone.sync();
    expect(pushed.pushed, 1);

    final row = server.rows['notes/n1']!;
    expect(String.fromCharCodes(row.dataBlob!), isNot(contains('Groceries')));

    final pulled = await laptop.sync();
    expect(pulled.applied, 1);
    expect((await laptop.store.get('n1'))!.json,
        {'title': 'Groceries', 'body': 'milk'});
    expect((await laptop.store.get('n1'))!.dirty, isFalse);

    // Nothing new on the second pull.
    expect((await laptop.sync()).applied, 0);
    // The pushing device does not re-apply its own row.
    expect((await phone.sync()).applied, 0);
  });

  test('deletes reach other devices as tombstones', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('n1', {'title': 'x'});
    await phone.sync();
    await laptop.sync();

    now = now.add(const Duration(minutes: 1));
    await phone.delete('n1');
    await phone.sync();
    expect(server.rows['notes/n1']!.dataBlob, isNull);

    await laptop.sync();
    final local = (await laptop.store.get('n1'))!;
    expect(local.deleted, isTrue);
    expect(local.json, isNull);
  });

  test('newer edit wins and the losing local edit is reported', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('n1', {'v': 0});
    await phone.sync();
    await laptop.sync();

    now = now.add(const Duration(minutes: 1));
    await laptop.save('n1', {'v': 'laptop'}); // older, not yet synced
    now = now.add(const Duration(minutes: 1));
    await phone.save('n1', {'v': 'phone'});
    await phone.sync();

    // Laptop pulls the newer edit first, so its older one is reported and
    // never pushed over it.
    final phoneRow = server.rows['notes/n1']!;
    final result = await laptop.sync();
    expect(result.conflicts.single.lostLocal.json, {'v': 'laptop'});
    expect(result.pushed, 0);
    expect((await laptop.store.get('n1'))!.json, {'v': 'phone'});
    expect(server.rows['notes/n1']!.updatedAt, phoneRow.updatedAt);

    // An older remote never overwrites a newer local edit.
    await phone.sync();
    expect((await phone.store.get('n1'))!.json, {'v': 'phone'});
  });

  test('a push rejected as stale stays dirty and is reported next sync',
      () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('n1', {'v': 0});
    await phone.sync();
    await laptop.sync();

    now = now.add(const Duration(minutes: 1));
    await laptop.save('n1', {'v': 'laptop'});
    // The phone writes a newer version after the laptop pulled, before its
    // push lands.
    server.beforePush = () async {
      now = now.add(const Duration(minutes: 1));
      await phone.save('n1', {'v': 'phone'});
      await phone.sync();
    };
    final first = await laptop.sync();
    expect(first.pushed, 0);
    expect((await laptop.store.get('n1'))!.dirty, isTrue);

    final second = await laptop.sync();
    expect(second.conflicts.single.lostLocal.json, {'v': 'laptop'});
    expect((await laptop.store.get('n1'))!.json, {'v': 'phone'});
  });

  test('a blob moved to another item id is rejected', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('secret', {'pin': '1234'});
    await phone.sync();

    final real = server.rows['notes/secret']!;
    server.inject(
      'notes',
      RemoteItem(
        itemId: 'public',
        updatedAt: real.updatedAt,
        deviceId: real.deviceId,
        dataBlob: real.dataBlob,
        signature: real.signature,
      ),
    );

    final result = await laptop.sync();
    expect(result.rejected, ['public']);
    expect(await laptop.store.get('public'), isNull);
    expect((await laptop.store.get('secret'))!.json, {'pin': '1234'});
  });

  test('unsigned, re-dated and foreign-key rows are rejected', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('n1', {'v': 1});
    await phone.sync();
    final real = server.rows['notes/n1']!;

    server.inject(
      'notes',
      RemoteItem(
          itemId: 'n2',
          updatedAt: real.updatedAt,
          deviceId: 'x',
          dataBlob: real.dataBlob),
    );
    // Same blob and signature, but a later timestamp to win LWW.
    server.inject(
      'notes',
      RemoteItem(
        itemId: 'n1',
        updatedAt: real.updatedAt.add(const Duration(days: 1)),
        deviceId: real.deviceId,
        dataBlob: real.dataBlob,
        signature: real.signature,
      ),
    );
    // Someone else's account writing into ours.
    final otherKey = await KeyHierarchy.appKey(
        Uint8List.fromList(List.filled(32, 9)), 'notes');
    final intruder = await device('intruder', key: otherKey);
    await intruder.save('n3', {'v': 'evil'});
    await intruder.sync();

    final result = await laptop.sync();
    expect(result.rejected.toSet(), {'n1', 'n2', 'n3'});
    expect(await laptop.store.get('n1'), isNull);
    expect(await laptop.store.get('n3'), isNull);
  });

  test('overlapping syncs push each change exactly once', () async {
    final phone = await device('phone');
    var pushes = 0;
    final counting = _CountingBackend(server, () => pushes++);
    final engine = ItemSyncEngine(
      appId: 'notes',
      appKey: appKey,
      deviceId: 'phone',
      store: phone.store,
      backend: counting,
      signingKeys: signing,
      clock: () => now,
    );
    await engine.save('n1', {'v': 1});
    await Future.wait([engine.sync(), engine.sync(), engine.sync()]);
    expect(pushes, 1);
  });

  group('clock', () {
    test('a phone whose clock is behind still wins with a later edit',
        () async {
      final phone = await device('phone');
      final laptop = await device('laptop');
      await laptop.save('n1', {'v': 'laptop'});
      await laptop.sync();
      await phone.sync();

      // The phone's clock is an hour behind; its edit comes later in reality.
      final slow = ItemSyncEngine(
        appId: 'notes',
        appKey: appKey,
        deviceId: 'phone',
        store: phone.store,
        backend: server,
        signingKeys: signing,
        clock: () => now.subtract(const Duration(hours: 1)),
      );
      await slow.save('n1', {'v': 'phone, later'});
      expect((await slow.sync()).pushed, 1);
      await laptop.sync();
      expect((await laptop.store.get('n1'))!.json, {'v': 'phone, later'});
    });

    test('the logical clock survives a restart', () async {
      final phone = await device('phone');
      await phone.save('n1', {'v': 1});
      await phone.sync();
      await phone.sync(); // pulls its own row: the server time is known
      final first = (await phone.store.get('n1'))!.updatedAt;
      now = now.subtract(const Duration(hours: 1)); // clock jumped back
      final restarted = ItemSyncEngine(
        appId: 'notes',
        appKey: appKey,
        deviceId: 'phone',
        store: phone.store,
        backend: server,
        signingKeys: signing,
        clock: () => now,
      );
      await restarted.save('n1', {'v': 2});
      expect((await phone.store.get('n1'))!.updatedAt.isAfter(first), isTrue);
    });

    test('a phone whose clock runs far ahead is held until it is due',
        () async {
      final fast = await device('fast');
      final laptop = await device('laptop');
      now = now.add(const Duration(hours: 2)); // only this phone's clock
      await fast.save('n1', {'v': 'from the future'});
      final result = await fast.sync();
      expect(result.pushed, 0);
      expect((await fast.store.get('n1'))!.dirty, isTrue);
      expect(server.rows, isEmpty);

      // Once the server's time catches up, it goes through.
      server.serverNow = () => now;
      expect((await fast.sync()).pushed, 1);
      await laptop.sync();
      expect((await laptop.store.get('n1'))!.json, {'v': 'from the future'});
    });

    test('a corrected fast clock does not hold back later edits', () async {
      final phone = await device('phone');
      now = now.add(const Duration(days: 1)); // clock a day ahead
      await phone.save('a', {'v': 'while fast'});
      expect((await phone.sync()).pushed, 0);
      now = now.subtract(const Duration(days: 1)); // corrected

      await phone.save('b', {'v': 'after the fix'});
      final result = await phone.sync();
      expect(result.pushed, 1);
      expect(server.rows.keys, ['notes/b']);
      expect((await phone.store.get('a'))!.dirty, isTrue); // held, not lost
    });

    test('a store error while seeding the clock is retried', () async {
      final phone = ItemSyncEngine(
        appId: 'notes',
        appKey: appKey,
        deviceId: 'phone',
        store: _FlakyStore(),
        backend: server,
        signingKeys: signing,
        clock: () => now,
      );
      await expectLater(phone.save('n1', {'v': 1}), throwsException);
      await phone.save('n1', {'v': 1});
      expect((await phone.sync()).pushed, 1);
    });

    test('a far-future row already on the server does not drag the clock',
        () async {
      final phone = await device('phone');
      final future = await device('future');
      now = now.add(const Duration(days: 1));
      await future.save('old', {'v': 'stamped a day ahead'});
      server.guardFuture = false; // written before the guard existed
      await future.sync();
      server.guardFuture = true;
      now = now.subtract(const Duration(days: 1));

      await phone.sync();
      await phone.save('n2', {'v': 'today'});
      expect((await phone.sync()).pushed, 1);
    });
  });

  test('a row committed out of order is still pulled', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('a', {'v': 'a'});
    await phone.save('b', {'v': 'b'});
    await phone.sync();
    // 'a' got its synced_at first but committed after 'b' was pulled.
    server.uncommitted.add('a');
    server.backdate('notes', 'a', const Duration(seconds: 5));
    await laptop.sync();
    expect(await laptop.store.get('a'), isNull);

    server.uncommitted.clear();
    await laptop.sync();
    expect((await laptop.store.get('a'))!.json, {'v': 'a'});
  });

  test('rejected rows are retried and read once they verify', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    await phone.save('n1', {'v': 1});
    await phone.sync();
    final good = server.rows['notes/n1']!;
    server.inject(
      'notes',
      RemoteItem(
          itemId: 'n1',
          updatedAt: good.updatedAt,
          deviceId: good.deviceId,
          dataBlob: good.dataBlob), // signature lost
    );
    expect((await laptop.sync()).rejected, ['n1']);
    expect((await laptop.sync()).rejected, ['n1'], reason: 'still retried');

    server.rows['notes/n1'] = good; // fixed without a newer synced_at
    final fixed = await laptop.sync();
    expect(fixed.rejected, isEmpty);
    expect((await laptop.store.get('n1'))!.json, {'v': 1});
    expect(await laptop.store.rejectedIds(), isEmpty);
  });

  test('many changes go up in batches', () async {
    final phone = ItemSyncEngine(
      appId: 'notes',
      appKey: appKey,
      deviceId: 'phone',
      store: InMemoryItemStore(),
      backend: server,
      signingKeys: signing,
      clock: () => now,
      pushBatchSize: 200,
    );
    for (var i = 0; i < 450; i++) {
      await phone.save('n$i', {'i': i});
    }
    expect((await phone.sync()).pushed, 450);
    expect(server.pushBatches, [200, 200, 50]);
    expect(await phone.store.dirtyItems(), isEmpty);
  });

  test('live updates are applied as they arrive', () async {
    final phone = await device('phone');
    final laptop = await device('laptop');
    final applied = Completer<SyncResult>();
    laptop.startLive(onApplied: applied.complete);

    await phone.save('n1', {'v': 'live'});
    await phone.sync();

    expect((await applied.future).applied, 1);
    expect((await laptop.store.get('n1'))!.json, {'v': 'live'});
    await laptop.stopLive();
  });

  test('the engine keeps its own key copy and refuses to run once closed',
      () async {
    server.serverNow = () => DateTime.now().toUtc(); // fromVault: real clock
    now = DateTime.now().toUtc();
    final callerKey = Uint8List.fromList(appKey);
    final phone = await ItemSyncEngine.fromVault(
      appId: 'notes',
      appKey: callerKey,
      deviceId: 'phone',
      store: InMemoryItemStore(),
      backend: server,
    );
    // The vault zeroes its key on lock; the engine's copy is unaffected.
    callerKey.fillRange(0, callerKey.length, 0);
    await phone.save('n1', {'v': 1});
    expect((await phone.sync()).pushed, 1);
    final laptop = await device('laptop');
    await laptop.sync();
    expect((await laptop.store.get('n1'))!.json, {'v': 1});

    // Closed (vault locked): nothing is sealed with a zeroed key.
    await phone.save('n2', {'secret': true});
    await phone.close();
    await expectLater(phone.sync(), throwsStateError);
    expect(server.rows.containsKey('notes/n2'), isFalse);
    expect(await phone.store.rejectedIds(), isEmpty);
  });
}

/// Fails the first `all()` read, like a database still opening.
class _FlakyStore extends InMemoryItemStore {
  bool _failed = false;

  @override
  Future<List<LocalItem>> all() {
    if (!_failed) {
      _failed = true;
      return Future.error(Exception('database locked'));
    }
    return super.all();
  }
}

class _CountingBackend implements SyncBackend {
  _CountingBackend(this._inner, this._onPush);
  final SyncBackend _inner;
  final void Function() _onPush;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      _inner.pull(app, since: since);

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) =>
      _inner.fetch(app, itemIds);

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    for (final _ in items) {
      _onPush();
    }
    await Future<void>.delayed(Duration.zero);
    return _inner.pushAll(app, items);
  }

  @override
  Future<void> Function() subscribe(
          String app, void Function(RemoteItem) onChange) =>
      _inner.subscribe(app, onChange);
}
