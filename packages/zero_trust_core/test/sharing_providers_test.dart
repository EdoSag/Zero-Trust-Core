import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';
import 'support/fake_sync_backend.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';

class _Account extends AccountService {
  _Account(this.id) : super(FakeBackend());
  final String id;
  @override
  String? get currentUserId => id;
}

class _MemoryOpener implements SpaceStoreOpener {
  final Map<String, InMemoryItemStore> stores = {};
  @override
  Future<LocalItemStore> open(String spaceId) async =>
      stores.putIfAbsent(spaceId, InMemoryItemStore.new);
  @override
  Future<void> delete(String spaceId) async => stores.remove(spaceId);
  @override
  Future<void> closeAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySpaceServer server;

  ProviderContainer phone(String userId, int seed) {
    final opener = _MemoryOpener();
    final c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'meds', displayName: 'Zero-Trust Meds')),
      accountServiceProvider.overrideWithValue(_Account(userId)),
      ztSyncBackendProvider.overrideWithValue(
          FakeSyncBackend()..serverNow = () => DateTime.now().toUtc()),
      ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()),
      ztLocalStoreProvider.overrideWith((ref) async {
        final appKey = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (appKey == null) throw const VaultIsLocked();
        final store = await ZtLocalStore.open(appKey: appKey);
        ref.onDispose(store.close);
        return store;
      }),
      ztSpaceBackendProvider.overrideWithValue(server.backendFor(userId)),
      ztSpaceStoreOpenerProvider.overrideWithValue(opener),
    ]);
    addTearDown(c.dispose);
    c.listen(ztSyncControllerProvider, (_, __) {});
    c.listen(ztSpacesProvider, (_, __) {});
    return c;
  }

  Future<SpacesState> settled(
      ProviderContainer c, bool Function(SpacesState) test) async {
    for (var i = 0; i < 400; i++) {
      final s = c.read(ztSpacesProvider);
      if (test(s)) return s;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('spaces never settled: ${c.read(ztSpacesProvider).entries}');
  }

  setUp(() => server = InMemorySpaceServer());

  test('two phones share a space end to end through the providers', () async {
    final a = phone(alice, 1);
    final b = phone(bob, 2);
    await a
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 1)));
    await b
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 2)));
    await settled(a, (s) => s.ready && !s.loading);

    final spaces = a.read(ztSpacesProvider.notifier);
    final space = await spaces.create(myName: 'Alice');
    await spaces.save(space.id, 'child', {'kind': 'child', 'name': 'Noa'});
    await spaces.syncNow(space.id);

    final link = await spaces.invite(space.id);
    final joined = await b
        .read(ztSpacesProvider.notifier)
        .answer(SpaceInviteLink.parse('$link'), myName: 'Bob');
    final pending = await spaces.pendingJoins(space.id);
    expect(pending.single.verificationCode, joined.verificationCode);
    await spaces.confirm(pending.single);

    final state = await settled(
        b,
        (s) =>
            s[space.id]?.space != null &&
            s[space.id]!.status.lastSyncedAt != null);
    expect(state[space.id]!.joinCode, joined.verificationCode);
    final child = await state[space.id]!.space!.store.get('child');
    expect(child?.json?['name'], 'Noa');

    // Locking closes everything.
    b.read(vaultControllerProvider.notifier).lock();
    await settled(b, (s) => !s.ready && s.entries.isEmpty);
  });
}
