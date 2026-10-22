import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

void main() {
  late Directory dir;
  late Uint8List appKey;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zt_store');
    appKey = await KeyHierarchy.appKey(
        Uint8List.fromList(List.generate(32, (i) => i)), 'notes');
  });
  tearDown(() => dir.delete(recursive: true));

  String path() => '${dir.path}/zt_notes_user.db';

  test('keeps items and sync state across reopening', () async {
    final at = DateTime.utc(2026, 10, 22, 9, 30, 0, 123, 456);
    var store = await ZtLocalStore.open(appKey: appKey, path: path());
    await store.put(LocalItem(
        itemId: 'a', updatedAt: at, json: {'title': 'Hi'}, dirty: true));
    await store.put(LocalItem(itemId: 'b', updatedAt: at, deleted: true));
    await store.setLastPulledAt(at);
    await store.setRejectedIds({'x', 'y'});
    await store.markLegacyImportDone('notes-v1');
    await store.close();

    store = await ZtLocalStore.open(appKey: appKey, path: path());
    addTearDown(store.close);
    final a = (await store.get('a'))!;
    expect(a.json, {'title': 'Hi'});
    expect(a.updatedAt, at);
    expect(a.dirty, isTrue);
    final b = (await store.get('b'))!;
    expect(b.deleted, isTrue);
    expect(b.json, isNull);
    expect(await store.get('missing'), isNull);
    expect((await store.all()).length, 2);
    expect((await store.liveItems()).map((i) => i.itemId), ['a']);
    expect((await store.dirtyItems()).map((i) => i.itemId), ['a']);
    expect(await store.lastPulledAt(), at);
    expect(await store.rejectedIds(), {'x', 'y'});
    expect(await store.legacyImportDone('notes-v1'), isTrue);
    expect(await store.legacyImportDone('notes-v2'), isFalse);
  });

  test('the file is encrypted: no item text, ids or SQLite header', () async {
    final store = await ZtLocalStore.open(appKey: appKey, path: path());
    await store.put(LocalItem(
        itemId: 'item-id-123',
        updatedAt: DateTime.utc(2026),
        json: {'title': 'Secret groceries'}));
    await store.close();

    final bytes = [
      for (final suffix in ['', '-wal'])
        if (File('${path()}$suffix').existsSync())
          ...File('${path()}$suffix').readAsBytesSync(),
    ];
    final text = String.fromCharCodes(bytes);
    expect(text, isNot(contains('Secret groceries')));
    expect(text, isNot(contains('item-id-123')));
    expect(text, isNot(contains('SQLite format 3')));
  });

  test('another key cannot open the file, and moveAside makes room', () async {
    final store = await ZtLocalStore.open(appKey: appKey, path: path());
    await store.put(LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026)));
    await store.close();

    final other = Uint8List.fromList(List.filled(32, 1));
    await expectLater(ZtLocalStore.open(appKey: other, path: path()),
        throwsA(isA<LocalStoreUnreadable>()));

    await ZtLocalStore.moveAside(path());
    expect(dir.listSync().where((f) => f.path.contains('.db.unreadable-')),
        isNotEmpty);
    final fresh = await ZtLocalStore.open(appKey: other, path: path());
    expect(await fresh.all(), isEmpty);
    await fresh.close();

    await ZtLocalStore.deleteFiles(path());
    expect(File(path()).existsSync(), isFalse);
  });

  test('a zeroed caller key mid-open does not change the store key', () async {
    final callerKey = Uint8List.fromList(appKey);
    final opening = ZtLocalStore.open(appKey: callerKey, path: path());
    callerKey.fillRange(0, callerKey.length, 0); // the vault locked
    await (await opening).close();
    // Opens with the real key, so the store was keyed from the copy.
    await (await ZtLocalStore.open(appKey: appKey, path: path())).close();
  });

  test('reports changed ids', () async {
    final store = await ZtLocalStore.open(appKey: appKey);
    addTearDown(store.close);
    final changes = <Set<String>>[];
    final sub = store.changes.listen(changes.add);
    await store.put(LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026)));
    await Future<void>.delayed(Duration.zero);
    expect(changes, [
      {'a'}
    ]);
    await sub.cancel();
  });

  test('two devices sync through it', () async {
    // fromVault engines use the real clock.
    final server = FakeSyncBackend()..serverNow = () => DateTime.now().toUtc();
    final phoneStore = await ZtLocalStore.open(appKey: appKey);
    final laptopStore = await ZtLocalStore.open(appKey: appKey);
    addTearDown(phoneStore.close);
    addTearDown(laptopStore.close);
    Future<ItemSyncEngine> engine(String id, LocalItemStore store) =>
        ItemSyncEngine.fromVault(
            appId: 'notes',
            appKey: appKey,
            deviceId: id,
            store: store,
            backend: server);
    final phone = await engine('phone', phoneStore);
    final laptop = await engine('laptop', laptopStore);

    await phone.save('n1', {'title': 'Groceries'});
    expect((await phone.sync()).pushed, 1);
    expect(await phoneStore.dirtyItems(), isEmpty);
    expect((await laptop.sync()).applied, 1);
    expect((await laptopStore.get('n1'))!.json, {'title': 'Groceries'});
    expect(await laptopStore.lastPulledAt(), isNotNull);
  });
}
