import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncBackend server;
  late InMemoryDeviceIdStore ids;
  late List<ZtLocalStore> stores;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes')),
      ztSyncBackendProvider.overrideWithValue(server),
      ztDeviceIdStoreProvider.overrideWithValue(ids),
      ztLocalStoreProvider.overrideWith((ref) async {
        final appKey = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (appKey == null) throw const VaultIsLocked();
        final store = await ZtLocalStore.open(appKey: appKey);
        stores.add(store);
        ref.onDispose(store.close);
        return store;
      }),
    ]);
    addTearDown(c.dispose);
    // Keep the controller alive, as a mounted settings screen would.
    c.listen(ztSyncControllerProvider, (_, __) {});
    return c;
  }

  Future<SyncStatus> settled(
      ProviderContainer c, bool Function(SyncStatus) test) async {
    for (var i = 0; i < 200; i++) {
      final s = c.read(ztSyncControllerProvider);
      if (test(s)) return s;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('sync status never settled: ${c.read(ztSyncControllerProvider)}');
  }

  setUp(() {
    // These engines use the real clock.
    server = FakeSyncBackend()..serverNow = () => DateTime.now().toUtc();
    ids = InMemoryDeviceIdStore();
    stores = [];
  });

  test('device id is created once and kept', () async {
    final first = await loadOrCreateDeviceId(ids);
    expect(
        first,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(await loadOrCreateDeviceId(ids), first);
    expect(await loadOrCreateDeviceId(InMemoryDeviceIdStore()), isNot(first));
  });

  test('locked: idle status, and saving is refused', () async {
    final c = container();
    expect(c.read(ztSyncControllerProvider).lastSyncedAt, isNull);
    await expectLater(c.read(ztSyncControllerProvider.notifier).save('n1', {}),
        throwsA(isA<VaultIsLocked>()));
  });

  test('syncs on unlock, pushes saves, and stops on lock', () async {
    final c = container();
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 3)));
    await c.read(ztSyncEngineProvider.future);
    final first = await settled(c, (s) => s.lastSyncedAt != null);
    expect(first.error, isNull);

    final controller = c.read(ztSyncControllerProvider.notifier);
    await controller.save('n1', {'title': 'Hello'});
    await controller.syncNow();
    expect(server.rows.containsKey('notes/n1'), isTrue);
    expect(server.rows['notes/n1']!.deviceId, ids.id);

    c.read(vaultControllerProvider.notifier).lock();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(ztSyncControllerProvider).lastSyncedAt, isNull);
    // The store closed with the vault.
    await expectLater(stores.single.all(), throwsA(anything));
  });

  test('imports legacy data once, then drops the legacy key', () async {
    final c = container();
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 4)), legacyDek: true);
    await c.read(ztSyncEngineProvider.future);
    await settled(c, (s) => s.lastSyncedAt != null);

    var reads = 0;
    final importer = LegacyImporter(
      source: 'notes-v1',
      read: (key) async {
        reads++;
        return const [
          LegacyRecord(itemId: 'old-1', json: {'t': 'old'})
        ];
      },
    );
    final controller = c.read(ztSyncControllerProvider.notifier);
    final results = await controller.importLegacy([importer]);
    expect(results.single.imported, 1);
    expect(
        (c.read(vaultControllerProvider) as VaultUnlocked).legacyKey, isNull);

    // The engine wasn't rebuilt by dropping the key, and the item syncs.
    await controller.syncNow();
    expect(server.rows.containsKey('notes/old-1'), isTrue);

    final again = await controller.importLegacy([importer]);
    expect(again.single.alreadyDone, isTrue);
    expect(reads, 1);
    expect(stores, hasLength(1));
  });
}
