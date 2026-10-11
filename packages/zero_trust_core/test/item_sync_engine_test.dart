import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// In-memory `vault_items`: one row per (app, item), stamped with a server
/// receive time like the `synced_at` trigger does.
class FakeSyncBackend implements SyncBackend {
  final Map<String, RemoteItem> rows = {};
  final List<void Function(RemoteItem)> _listeners = [];
  int _tick = 0;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    final out = rows.entries
        .where((e) => e.key.startsWith('$app/'))
        .map((e) => e.value)
        .where((r) => since == null || r.syncedAt!.isAfter(since))
        .toList()
      ..sort((a, b) => a.syncedAt!.compareTo(b.syncedAt!));
    return out;
  }

  @override
  Future<void> push(String app, RemoteItem item) async {
    // Mirrors the vault_items guard trigger: an older write never replaces
    // a newer row.
    final existing = rows['$app/${item.itemId}'];
    if (existing != null && item.updatedAt.isBefore(existing.updatedAt)) return;
    final stored = _withSyncedAt(item);
    rows['$app/${item.itemId}'] = stored;
    for (final l in List.of(_listeners)) {
      l(stored);
    }
  }

  /// Writes a row as a hostile server or another user could.
  void inject(String app, RemoteItem item) =>
      rows['$app/${item.itemId}'] = _withSyncedAt(item);

  RemoteItem _withSyncedAt(RemoteItem item) => RemoteItem(
        itemId: item.itemId,
        updatedAt: item.updatedAt,
        deviceId: item.deviceId,
        dataBlob: item.dataBlob,
        signature: item.signature,
        deleted: item.deleted,
        syncedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_tick)),
      );

  @override
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange) {
    _listeners.add(onChange);
    return () async => _listeners.remove(onChange);
  }
}

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
}

class _CountingBackend implements SyncBackend {
  _CountingBackend(this._inner, this._onPush);
  final SyncBackend _inner;
  final void Function() _onPush;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      _inner.pull(app, since: since);

  @override
  Future<void> push(String app, RemoteItem item) async {
    _onPush();
    await Future<void>.delayed(Duration.zero);
    await _inner.push(app, item);
  }

  @override
  Future<void> Function() subscribe(
          String app, void Function(RemoteItem) onChange) =>
      _inner.subscribe(app, onChange);
}
