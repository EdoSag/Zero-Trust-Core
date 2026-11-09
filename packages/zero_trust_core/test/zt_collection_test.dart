import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_sync_backend.dart';

class Note {
  const Note(this.id, this.title, {this.pinned = false, this.at});
  final String id;
  final String title;
  final bool pinned;
  final DateTime? at;
}

class Notebook {
  const Notebook(this.id, this.name);
  final String id;
  final String name;
}

/// The default collection: no `kind`, like every note Notes ever wrote.
/// Version 2 added `pinned`.
final notes = ZtCollection<Note>(
  kind: null,
  version: 2,
  fromJson: (id, json, at) =>
      Note(id, json['title'] as String, pinned: json['pinned'] as bool, at: at),
  toJson: (n) => {'title': n.title, 'pinned': n.pinned},
  idOf: (n) => n.id,
  upgrade: (json, from) => {...json, 'pinned': false},
);

final notebooks = ZtCollection<Notebook>(
  kind: 'notebook',
  fromJson: (id, json, _) => Notebook(id, json['name'] as String),
  toJson: (b) => {'name': b.name},
  idOf: (b) => b.id,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;
  late ZtLocalStore store;
  late FakeSyncBackend server;

  setUp(() async {
    server = FakeSyncBackend()..serverNow = () => DateTime.now().toUtc();
    c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes')),
      ztSyncBackendProvider.overrideWithValue(server),
      ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()),
      ztLocalStoreProvider.overrideWith((ref) async {
        final appKey = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (appKey == null) throw const VaultIsLocked();
        final s = await ZtLocalStore.open(appKey: appKey);
        ref.onDispose(s.close);
        return s;
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(ztSyncControllerProvider, (_, __) {});
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 5)));
    await c.read(ztSyncEngineProvider.future);
    store = await c.read(ztLocalStoreProvider.future) as ZtLocalStore;
  });

  SyncController sync() => c.read(ztSyncControllerProvider.notifier);

  test('items without a kind (written before collections) stay readable',
      () async {
    // Exactly what Notes stores today.
    await sync().save('old', {'title': 'Written by Notes 0.6'});
    await sync().save('nb', {'kind': 'notebook', 'name': 'Work'});

    final all = await notes.list(store);
    expect(all.single.id, 'old');
    expect(all.single.title, 'Written by Notes 0.6');
    expect(all.single.pinned, isFalse, reason: 'upgraded from version 1');
    expect((await notebooks.list(store)).single.name, 'Work');
  });

  test('save adds kind and version, and keeps unknown fields', () async {
    await sync().save('n1', {
      'title': 'x',
      'pinned': false,
      '_v': 2,
      'colour': 'red', // added by a newer build at the same version
    });
    await notes.save(sync(), store, const Note('n1', 'renamed', pinned: true));
    final json = (await store.get('n1'))!.json!;
    expect(json, {
      'title': 'renamed',
      'pinned': true,
      '_v': 2,
      'colour': 'red',
    });
    expect(json.containsKey('kind'), isFalse,
        reason: 'the default collection writes no kind, as Notes expects');

    await notebooks.save(sync(), store, const Notebook('b1', 'Home'));
    expect((await store.get('b1'))!.json,
        {'name': 'Home', 'kind': 'notebook', '_v': 1});
  });

  test('items from a newer app version are listed, not shown or overwritten',
      () async {
    await sync().save('future', {'title': 'x', 'pinned': true, '_v': 3});
    expect(await notes.list(store), isEmpty);
    final newer = await notes.newerItems(store);
    expect(newer.single.itemId, 'future');
    expect(newer.single.version, 3);
    await expectLater(notes.save(sync(), store, const Note('future', 'y')),
        throwsA(isA<ItemFromNewerVersion>()));
    expect((await store.get('future'))!.json!['title'], 'x');
  });

  test('watch emits now and after changes; delete removes on every device',
      () async {
    final seen = <String>[];
    final sub = notes.watch(store).listen(
        (v) => seen.add(([for (final n in v) n.title]..sort()).join(',')));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await notes.save(sync(), store, const Note('a', 'A'));
    await pumpEventQueue();
    await notes.delete(sync(), 'a');
    await pumpEventQueue();
    expect(seen.first, '');
    expect(seen, contains('A'));
    expect(seen.last, '');
    expect(await notes.get(store, 'a'), isNull);

    await sync().syncNow();
    expect(server.rows['notes/a']!.deleted, isTrue);
  });
}
