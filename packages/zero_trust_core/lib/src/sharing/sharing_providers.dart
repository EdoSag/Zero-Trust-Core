import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/zt_app_config.dart';
import '../core_providers.dart';
import '../sync/item_sync_engine.dart';
import '../sync/local_item_store.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_scheduler.dart';
import '../sync/zt_local_store.dart';
import '../vault/vault_controller.dart';
import 'shared_spaces.dart';
import 'space_backend.dart';
import 'space_codec.dart';
import 'space_invite_link.dart';
import 'supabase_space_backend.dart';

/// Which items of the app's shared spaces only admins may write. Apps
/// override it (Meds: children, medications and treatments).
final ztSpacePolicyProvider =
    Provider<SpacePolicy>((ref) => const SpacePolicy());

final ztSpaceBackendProvider =
    Provider<SpaceBackend>((ref) => SupabaseSpaceBackend());

/// Opens and deletes the encrypted local store of each shared space.
abstract interface class SpaceStoreOpener {
  Future<LocalItemStore> open(String spaceId);
  Future<void> delete(String spaceId);
  Future<void> closeAll();
}

/// One [ZtLocalStore] file per space, encrypted under this account's app
/// key (so it is unreadable while locked, like the app's own store).
class ZtSpaceStoreOpener implements SpaceStoreOpener {
  ZtSpaceStoreOpener(
      {required Uint8List appKey,
      required this.appId,
      required this.userId,
      @visibleForTesting Future<String> Function(String spaceId)? pathFor})
      : _appKey = Uint8List.fromList(appKey),
        _pathFor = pathFor;

  final Uint8List _appKey;
  final String appId;
  final String userId;
  final Future<String> Function(String spaceId)? _pathFor;

  /// Open and opening stores. An open that fails takes itself out again.
  final Map<String, Future<ZtLocalStore>> _stores = {};
  bool _closed = false;

  Future<String> _path(String spaceId) =>
      _pathFor?.call(spaceId) ??
      ZtLocalStore.pathFor(
          appId: '${appId}_space_${spaceId.replaceAll('-', '')}',
          userId: userId);

  @override
  Future<LocalItemStore> open(String spaceId) {
    if (_closed) throw const VaultIsLocked();
    return _stores[spaceId] ??= _openStore(spaceId);
  }

  Future<ZtLocalStore> _openStore(String spaceId) async {
    // Copy first: [closeAll] zeroes the key, maybe while this waits. With
    // a zeroed key the file would look unreadable and be moved aside.
    final key = Uint8List.fromList(_appKey);
    try {
      final path = await _path(spaceId);
      if (_closed) throw const VaultIsLocked();
      ZtLocalStore store;
      try {
        store = await ZtLocalStore.open(appKey: key, path: path);
      } on LocalStoreUnreadable {
        if (_closed) throw const VaultIsLocked();
        await ZtLocalStore.moveAside(path);
        store = await ZtLocalStore.open(appKey: key, path: path);
      }
      // Locked while opening: nobody would close this store later.
      if (_closed) {
        await store.close();
        throw const VaultIsLocked();
      }
      return store;
    } catch (_) {
      _stores.remove(spaceId)?.ignore();
      rethrow;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  @override
  Future<void> delete(String spaceId) async {
    final opening = _stores.remove(spaceId);
    if (opening != null) {
      try {
        await (await opening).close();
      } on Object {
        // It never opened.
      }
    }
    await ZtLocalStore.deleteFiles(await _path(spaceId));
  }

  @override
  Future<void> closeAll() async {
    _closed = true;
    final all = [..._stores.values];
    _stores.clear();
    _appKey.fillRange(0, _appKey.length, 0);
    for (final opening in all) {
      // One still opening sees [_closed], closes itself and fails here.
      try {
        await (await opening).close();
      } on Object {
        // Nothing was opened.
      }
    }
  }
}

final ztSpaceStoreOpenerProvider = Provider<SpaceStoreOpener>((ref) {
  final appKey = ref.watch(vaultControllerProvider
      .select((s) => s is VaultUnlocked ? s.appKey : null));
  if (appKey == null) throw const VaultIsLocked();
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final opener = ZtSpaceStoreOpener(
      appKey: appKey,
      appId: ref.watch(ztAppConfigProvider.select((c) => c.appId)),
      userId: userId);
  ref.onDispose(opener.closeAll);
  return opener;
});

/// The account's private notes about spaces, kept in the app's own synced
/// store (so every device of the account has them).
class _SyncedPrivateStore implements SpacePrivateStore {
  _SyncedPrivateStore(this._ref);
  final Ref _ref;

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final store = await _ref.read(ztLocalStoreProvider.future);
    final item = await store.get(id);
    return item == null || item.deleted ? null : item.json;
  }

  @override
  Future<void> write(String id, Map<String, Object?> json) =>
      _ref.read(ztSyncControllerProvider.notifier).save(id, json);

  @override
  Future<void> remove(String id) async {
    if (await read(id) == null) return;
    await _ref.read(ztSyncControllerProvider.notifier).delete(id);
  }
}

/// The app's [SharedSpaces] while the vault is unlocked; closed (keys
/// zeroed) when it locks.
final ztSharedSpacesProvider = FutureProvider<SharedSpaces>((ref) async {
  final identity = ref.watch(vaultControllerProvider
      .select((s) => s is VaultUnlocked ? s.identity : null));
  if (identity == null) throw const VaultIsLocked();
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final opener = ref.watch(ztSpaceStoreOpenerProvider);
  final deviceId = await ref.watch(ztDeviceIdProvider.future);
  final spaces = SharedSpaces(
    app: ref.watch(ztAppConfigProvider.select((c) => c.appId)),
    myUserId: userId,
    identity: identity,
    backend: ref.watch(ztSpaceBackendProvider),
    privateStore: _SyncedPrivateStore(ref),
    openStore: opener.open,
    deleteStore: opener.delete,
    deviceId: deviceId,
    policy: ref.watch(ztSpacePolicyProvider),
  );
  ref.onDispose(spaces.close);
  return spaces;
});

/// One space as the app shows it.
class SpaceEntry {
  const SpaceEntry({
    required this.info,
    this.space,
    this.status = const SyncStatus(),
    this.joinCode,
  });

  final SpaceInfo info;

  /// Null while this device can't vouch for the space yet (see
  /// [SpaceNotTrusted]).
  final SharedSpace? space;
  final SyncStatus status;

  /// For a space this account joined: the code to compare with the admin.
  final String? joinCode;

  SpaceEntry _with({SyncStatus? status}) => SpaceEntry(
      info: info,
      space: space,
      status: status ?? this.status,
      joinCode: joinCode);
}

class SpacesState {
  const SpacesState({
    this.entries = const [],
    this.loading = true,
    this.ready = false,
    this.error,
  });
  final List<SpaceEntry> entries;
  final bool loading;

  /// The vault is unlocked and spaces can be created, joined and used.
  final bool ready;
  final Object? error;

  SpaceEntry? operator [](String spaceId) {
    for (final e in entries) {
      if (e.info.id == spaceId) return e;
    }
    return null;
  }
}

/// Keeps every shared space of the app in sync while the vault is unlocked:
/// on unlock and resume, 2 s after edits, every 5 minutes, live as other
/// members write, and when memberships or keys change. Its state lists the
/// spaces with their sync status. Apps act on spaces through it.
class SpacesController extends Notifier<SpacesState> {
  SharedSpaces? _spaces;
  final Map<String, SyncScheduler> _schedulers = {};
  Future<void>? _refreshing;
  bool _again = false;

  @override
  SpacesState build() {
    final spacesState = ref.watch(ztSharedSpacesProvider);
    _spaces = switch (spacesState) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final spaces = _spaces;
    if (spaces == null) {
      final error = spacesState.error;
      return SpacesState(
          loading: error == null, error: error is VaultIsLocked ? null : error);
    }
    final cancelWatch = spaces.backend.watch(spaces.app, () => refresh());
    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      lifecycle.dispose();
      cancelWatch();
      for (final s in _schedulers.values) {
        s.dispose();
      }
      _schedulers.clear();
    });
    scheduleMicrotask(refresh);
    return const SpacesState(ready: true);
  }

  SharedSpaces get _require => _spaces ?? (throw const VaultIsLocked());

  /// Re-reads the list of spaces and opens new ones.
  Future<void> refresh() {
    if (_refreshing != null) {
      _again = true;
      return _refreshing!;
    }
    return _refreshing = _refresh().whenComplete(() {
      _refreshing = null;
      if (_again) {
        _again = false;
        refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final spaces = _spaces;
    if (spaces == null) return;
    try {
      final infos = await spaces.list();
      final entries = <SpaceEntry>[];
      final listed = {for (final i in infos) i.id};
      for (final info in infos) {
        SharedSpace? space;
        try {
          space = await spaces.open(info.id);
        } on SpaceNotTrusted {
          space = null;
        }
        if (space != null && !_schedulers.containsKey(info.id)) {
          final s = space;
          final scheduler = SyncScheduler(
            sync: () => spaces.sync(s),
            onStatus: (st) => _setStatus(s.id, st),
          );
          _schedulers[info.id] = scheduler;
          s.engine.startLive(onApplied: scheduler.applyLive);
          scheduleMicrotask(scheduler.start);
        }
        entries.add(SpaceEntry(
          info: info,
          space: space,
          status: state[info.id]?.status ?? const SyncStatus(),
          joinCode: await spaces.joinCode(info.id),
        ));
      }
      // Spaces this account is no longer in: one last sync wipes them here.
      for (final gone in [..._schedulers.keys]) {
        if (listed.contains(gone)) continue;
        _schedulers.remove(gone)?.dispose();
        try {
          await spaces.sync(await spaces.open(gone));
        } on Object {
          // already forgotten
        }
      }
      state = SpacesState(entries: entries, loading: false, ready: true);
    } on Object catch (e) {
      state = SpacesState(
          entries: state.entries, loading: false, ready: true, error: e);
    }
  }

  void _setStatus(String spaceId, SyncStatus status) {
    state = SpacesState(
      entries: [
        for (final e in state.entries)
          e.info.id == spaceId ? e._with(status: status) : e,
      ],
      loading: state.loading,
      ready: state.ready,
      error: state.error,
    );
  }

  Future<SharedSpace> _space(String spaceId) => _require.open(spaceId);

  Future<void> save(
      String spaceId, String itemId, Map<String, Object?> json) async {
    await (await _space(spaceId)).save(itemId, json);
    _schedulers[spaceId]?.localChange();
  }

  Future<void> delete(String spaceId, String itemId) async {
    await (await _space(spaceId)).delete(itemId);
    _schedulers[spaceId]?.localChange();
  }

  Future<void> syncNow(String spaceId) =>
      _schedulers[spaceId]?.syncNow() ?? Future.value();

  Future<SharedSpace> create({required String myName}) async {
    final space = await _require.create(myName: myName);
    await refresh();
    return space;
  }

  Future<SpaceInviteLink> invite(String spaceId,
          {SpaceRole role = SpaceRole.member,
          Duration validFor = const Duration(days: 7)}) =>
      _require.invite(spaceId, role: role, validFor: validFor);

  Future<JoinStarted> answer(SpaceInviteLink link,
      {required String myName}) async {
    final started = await _require.answer(link, myName: myName);
    // Push the anchor note now, so the account's other devices learn it.
    await ref.read(ztSyncControllerProvider.notifier).syncNow();
    await refresh();
    return started;
  }

  Future<List<PendingJoin>> pendingJoins(String spaceId) =>
      _require.pendingJoins(spaceId);

  Future<void> confirm(PendingJoin join) async {
    await _require.confirm(join);
    await refresh();
  }

  Future<void> revokeInvite(String inviteId) => _require.revokeInvite(inviteId);

  Future<void> remove(String spaceId, String userId) async {
    await _require.remove(spaceId, userId);
    await refresh();
  }

  Future<void> setRole(String spaceId, String userId, SpaceRole role) async {
    await _require.setRole(spaceId, userId, role);
    await refresh();
  }

  Future<void> rename(String spaceId, String userId, String name) =>
      _require.rename(spaceId, userId, name);

  Future<void> leave(String spaceId) async {
    _schedulers.remove(spaceId)?.dispose();
    await _require.leave(spaceId);
    await refresh();
  }

  Future<void> deleteSpace(String spaceId) async {
    _schedulers.remove(spaceId)?.dispose();
    await _require.deleteSpace(spaceId);
    await refresh();
  }

  /// Every space's sync result, for a "Sync now" button.
  Future<List<SyncResult>> syncAll() async {
    final spaces = _require;
    return [
      for (final e in state.entries)
        if (e.space != null) await spaces.sync(e.space!),
    ];
  }
}

final ztSpacesProvider =
    NotifierProvider<SpacesController, SpacesState>(SpacesController.new);
