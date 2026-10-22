import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/zt_app_config.dart';
import '../core_providers.dart';
import '../vault/vault_controller.dart';
import 'device_id.dart';
import 'item_sync_engine.dart';
import 'legacy_importer.dart';
import 'local_item_store.dart';
import 'supabase_sync_backend.dart';
import 'sync_backend.dart';
import 'sync_scheduler.dart';
import 'zt_local_store.dart';

/// Thrown by the sync providers while the vault is locked.
class VaultIsLocked implements Exception {
  const VaultIsLocked();
  @override
  String toString() => 'VaultIsLocked';
}

/// The unlocked app key, or null while locked. Changes only on unlock and
/// lock, so providers built on it aren't rebuilt by other vault changes.
final _appKeyProvider = Provider<Uint8List?>((ref) => ref.watch(
    vaultControllerProvider
        .select((s) => s is VaultUnlocked ? s.appKey : null)));

final ztDeviceIdStoreProvider =
    Provider<DeviceIdStore>((ref) => SecureDeviceIdStore());

/// This install's stable device id.
final ztDeviceIdProvider = FutureProvider<String>(
    (ref) => loadOrCreateDeviceId(ref.watch(ztDeviceIdStoreProvider)));

final ztSyncBackendProvider =
    Provider<SyncBackend>((ref) => SupabaseSyncBackend());

/// The signed-in account's local store, open while the vault is unlocked
/// and closed when it locks. A [ZtLocalStore] unless an app overrides it.
///
/// A file this account's key can't open (damaged) is set aside as
/// `.unreadable-<time>` and a fresh store syncs everything down again.
final ztLocalStoreProvider = FutureProvider<LocalItemStore>((ref) async {
  final unlocked = ref.watch(_appKeyProvider);
  if (unlocked == null) throw const VaultIsLocked();
  // Copy before any await: locking zeroes the vault's buffer, and a store
  // opened with a zeroed key would look unreadable and be moved aside.
  final appKey = Uint8List.fromList(unlocked);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    appKey.fillRange(0, appKey.length, 0);
  });
  final appId = ref.watch(ztAppConfigProvider.select((c) => c.appId));
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final path = await ZtLocalStore.pathFor(appId: appId, userId: userId);
  if (disposed) throw const VaultIsLocked();
  ZtLocalStore store;
  try {
    store = await ZtLocalStore.open(appKey: appKey, path: path);
  } on LocalStoreUnreadable {
    if (disposed) throw const VaultIsLocked();
    await ZtLocalStore.moveAside(path);
    store = await ZtLocalStore.open(appKey: appKey, path: path);
  }
  if (disposed) {
    await store.close();
    throw const VaultIsLocked();
  }
  ref.onDispose(store.close);
  return store;
});

/// The sync engine for the unlocked vault, closed when it locks.
final ztSyncEngineProvider = FutureProvider<ItemSyncEngine>((ref) async {
  final unlocked = ref.watch(_appKeyProvider);
  if (unlocked == null) throw const VaultIsLocked();
  final appKey = Uint8List.fromList(unlocked); // see ztLocalStoreProvider
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    appKey.fillRange(0, appKey.length, 0);
  });
  final appId = ref.watch(ztAppConfigProvider.select((c) => c.appId));
  final backend = ref.watch(ztSyncBackendProvider);
  final store = await ref.watch(ztLocalStoreProvider.future);
  final deviceId = await ref.watch(ztDeviceIdProvider.future);
  if (disposed) throw const VaultIsLocked();
  final engine = await ItemSyncEngine.fromVault(
    appId: appId,
    appKey: appKey,
    deviceId: deviceId,
    store: store,
    backend: backend,
  );
  if (disposed) {
    await engine.close();
    throw const VaultIsLocked();
  }
  ref.onDispose(engine.close);
  return engine;
});

/// Runs sync for the app while the vault is unlocked: on unlock, on resume,
/// after edits, on a timer, with backoff after failures, plus realtime
/// changes from other devices (see [SyncScheduler]). Its state is the
/// shared sync status.
///
/// Apps save through [save] and [delete], so edits are pushed without each
/// screen having to ask.
class SyncController extends Notifier<SyncStatus> {
  SyncScheduler? _scheduler;
  ItemSyncEngine? _engine;

  @override
  SyncStatus build() {
    final engineState = ref.watch(ztSyncEngineProvider);
    // Only a finished build counts: while the engine provider rebuilds
    // (after a lock, say) `.value` still holds the previous, closed engine.
    final engine = switch (engineState) {
      AsyncData(:final value) => value,
      _ => null,
    };
    _engine = engine;
    _scheduler = null;
    if (engine == null) {
      // Locked or still opening is idle; a store that failed to open is not.
      final error = engineState.error;
      return error == null || error is VaultIsLocked
          ? const SyncStatus()
          : SyncStatus(error: error);
    }

    final scheduler = SyncScheduler(
      sync: engine.sync,
      onStatus: (s) => state = s,
    );
    _scheduler = scheduler;
    engine.startLive(onApplied: scheduler.applyLive);
    final lifecycle = AppLifecycleListener(
      onResume: scheduler.resume,
      onPause: scheduler.pause,
    );
    ref.onDispose(() {
      lifecycle.dispose();
      scheduler.dispose();
    });
    // Not during build: the first status change would be a nested update.
    scheduleMicrotask(scheduler.start);
    return scheduler.status;
  }

  ItemSyncEngine get _requireEngine => _engine ?? (throw const VaultIsLocked());

  Future<void> save(String itemId, Map<String, Object?> json) async {
    await _requireEngine.save(itemId, json);
    _scheduler?.localChange();
  }

  Future<void> delete(String itemId) async {
    await _requireEngine.delete(itemId);
    _scheduler?.localChange();
  }

  Future<void> syncNow() => _scheduler?.syncNow() ?? Future.value();

  void clearConflicts() => _scheduler?.clearConflicts();

  /// Runs each of [importers] once on this device (see [LegacyImporter]),
  /// then drops the legacy key, so pass every legacy source the app has.
  /// The local store must be a [LegacyImportLedger], as [ZtLocalStore] is.
  /// On failure the key is kept and the next call retries.
  Future<List<LegacyImportResult>> importLegacy(
      List<LegacyImporter> importers) async {
    final engine = _requireEngine;
    if (engine.store case final LegacyImportLedger ledger) {
      return _importLegacy(engine, ledger, importers);
    }
    throw StateError('The local store does not record imports');
  }

  Future<List<LegacyImportResult>> _importLegacy(
    ItemSyncEngine engine,
    LegacyImportLedger ledger,
    List<LegacyImporter> importers,
  ) async {
    final vault = ref.read(vaultControllerProvider);
    if (vault is! VaultUnlocked) throw const VaultIsLocked();
    final results = [
      for (final importer in importers)
        await importer.run(
          engine: engine,
          ledger: ledger,
          legacyKey: vault.legacyKey,
        ),
    ];
    ref.read(vaultControllerProvider.notifier).forgetLegacyKey();
    if (results.any((r) => r.imported > 0)) _scheduler?.localChange();
    return results;
  }
}

final ztSyncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);
