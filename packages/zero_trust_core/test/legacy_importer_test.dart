import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

class _Ledger implements LegacyImportLedger {
  final Set<String> done = {};

  @override
  Future<bool> legacyImportDone(String source) async => done.contains(source);

  @override
  Future<void> markLegacyImportDone(String source) async => done.add(source);
}

void main() {
  late FakeSyncBackend server;
  late Uint8List appKey;
  final legacyKey = Uint8List.fromList(List.filled(32, 5));

  Future<ItemSyncEngine> device(String id) async => ItemSyncEngine.fromVault(
        appId: 'notes',
        appKey: appKey,
        deviceId: id,
        store: InMemoryItemStore(),
        backend: server,
      );

  /// Old records "decrypted" with the legacy key; records the key it got.
  LegacyImporter importer(List<LegacyRecord> records,
          {List<Uint8List>? keys}) =>
      LegacyImporter(
        source: 'notes-v1',
        read: (key) async {
          expect(key, legacyKey);
          keys?.add(key);
          return records;
        },
      );

  setUp(() async {
    // These engines use the real clock.
    server = FakeSyncBackend()..serverNow = () => DateTime.now().toUtc();
    appKey = await KeyHierarchy.appKey(Uint8List(32), 'notes');
  });

  test('imports old records once, sealed under the app key', () async {
    final phone = await device('phone');
    final ledger = _Ledger();
    final keys = <Uint8List>[];
    final records = [
      const LegacyRecord(itemId: 'old-1', json: {'title': 'One'}),
      const LegacyRecord(itemId: 'old-2', json: {'title': 'Two'}),
    ];

    final result = await importer(records, keys: keys)
        .run(engine: phone, ledger: ledger, legacyKey: legacyKey);
    expect(result.imported, 2);
    expect(ledger.done, {'notes-v1'});
    // The importer's copy of the key is zeroed; the caller's is untouched.
    expect(keys.single.every((b) => b == 0), isTrue);
    expect(legacyKey.every((b) => b == 5), isTrue);

    await phone.sync();
    expect(server.rows.keys, containsAll(['notes/old-1', 'notes/old-2']));
    final laptop = await device('laptop');
    await laptop.sync();
    expect((await laptop.store.get('old-2'))!.json, {'title': 'Two'});

    final again = await importer(records)
        .run(engine: phone, ledger: ledger, legacyKey: legacyKey);
    expect(again.alreadyDone, isTrue);
  });

  test('never overwrites an item another device imported and edited', () async {
    final records = [
      const LegacyRecord(itemId: 'old-1', json: {'title': 'Original'}),
    ];
    final phone = await device('phone');
    await importer(records)
        .run(engine: phone, ledger: _Ledger(), legacyKey: legacyKey);
    await phone.save('old-1', {'title': 'Edited on phone'});
    await phone.sync();

    // The laptop imports later from the same old data.
    final laptop = await device('laptop');
    final result = await importer(records)
        .run(engine: laptop, ledger: _Ledger(), legacyKey: legacyKey);
    expect(result.imported, 0);
    expect(result.skipped, 1);
    await laptop.sync();
    expect(server.rows['notes/old-1'], isNotNull);
    expect(
        (await laptop.store.get('old-1'))!.json, {'title': 'Edited on phone'});
  });

  test('two devices importing at once: a later edit is never overwritten',
      () async {
    final records = [
      const LegacyRecord(itemId: 'old-1', json: {'title': 'Original'}),
    ];
    final phone = await device('phone');
    final laptop = await device('laptop');
    // The laptop's import has synced (nothing there yet) and is reading the
    // old data when the phone imports, the user edits, and it uploads.
    final result = await LegacyImporter(
      source: 'notes-v1',
      read: (_) async {
        await importer(records)
            .run(engine: phone, ledger: _Ledger(), legacyKey: legacyKey);
        await phone.save('old-1', {'title': 'Edited on phone'});
        await phone.sync();
        return records;
      },
    ).run(engine: laptop, ledger: _Ledger(), legacyKey: legacyKey);
    expect(result.imported, 1); // it hadn't seen the phone's copy

    await laptop.sync();
    await phone.sync();
    expect(
        (await laptop.store.get('old-1'))!.json, {'title': 'Edited on phone'});
    expect(
        (await phone.store.get('old-1'))!.json, {'title': 'Edited on phone'});
  });

  test('an account without a legacy key has nothing to import', () async {
    final ledger = _Ledger();
    final result = await LegacyImporter(
      source: 'notes-v1',
      read: (_) => fail('must not read'),
    ).run(engine: await device('phone'), ledger: ledger, legacyKey: null);
    expect(result.imported, 0);
    expect(ledger.done, {'notes-v1'});
  });

  test('offline: nothing is imported or marked done, so it retries', () async {
    final ledger = _Ledger();
    final engine = ItemSyncEngine(
      appId: 'notes',
      appKey: appKey,
      deviceId: 'phone',
      store: InMemoryItemStore(),
      backend: _OfflineBackend(),
      signingKeys: await KeyHierarchy.signingKeys(appKey),
    );
    await expectLater(
        importer(const [LegacyRecord(itemId: 'a', json: {})])
            .run(engine: engine, ledger: ledger, legacyKey: legacyKey),
        throwsException);
    expect(ledger.done, isEmpty);
    expect(await engine.store.all(), isEmpty);
  });
}

class _OfflineBackend implements SyncBackend {
  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      Future.error(Exception('offline'));

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) =>
      Future.error(Exception('offline'));

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) =>
      Future.error(Exception('offline'));

  @override
  Future<void> Function() subscribe(
          String app, void Function(RemoteItem) onChange) =>
      () async {};
}
