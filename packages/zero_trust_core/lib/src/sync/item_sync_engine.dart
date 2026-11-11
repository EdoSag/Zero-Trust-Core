import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'local_item_store.dart';
import 'sync_backend.dart';

/// A local edit that lost to a newer edit from another device. Kept so the
/// UI can offer "restore my version" instead of silently dropping it.
class SyncConflict {
  const SyncConflict({required this.itemId, required this.lostLocal});
  final String itemId;
  final LocalItem lostLocal;
}

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.applied = 0,
    this.conflicts = const [],
    this.rejected = const [],
    this.storageFull = false,
    this.tooLarge = const [],
  });

  final int pushed;

  /// Remote changes written to the local store.
  final int applied;
  final List<SyncConflict> conflicts;

  /// Item ids whose rows fail signature or decryption checks, after this
  /// sync's retries. Never applied, so a server or attacker cannot inject or
  /// swap data. Retried on every sync; while non-empty, the app should say
  /// that some items couldn't be read.
  final List<String> rejected;

  /// The server refused new data because the account is at its storage
  /// limit. Unpushed edits stay on this device and go up once space is
  /// freed (deleting is always allowed) or the limit is raised.
  final bool storageFull;

  /// Item ids bigger than the server's per-item cap. They stay on this
  /// device, waiting, until edited to be smaller.
  final List<String> tooLarge;
}

/// Encrypted per-item sync over the shared `vault_items` table, for any app.
///
/// - Every item is sealed under the app key with the item id as AAD, and
///   signed with the user's Ed25519 key over (app, id, updatedAt, deleted,
///   blob), so the server only ever stores opaque, tamper-evident rows.
/// - Conflicts resolve last-writer-wins on `updatedAt` (device id breaks
///   ties); a losing local edit is reported in [SyncResult.conflicts].
///   `updatedAt` comes from a hybrid logical clock: never earlier than any
///   version this device has seen, so a phone whose clock is behind still
///   wins with a later edit.
/// - Deletes are tombstones, so they reach every device. The server removes
///   tombstones after [tombstoneRetention]; a device that hasn't pulled for
///   [fullResyncAfter] pulls everything again and drops what the server no
///   longer has.
/// - Deletes are pushed before edits, and the server never refuses them, so
///   an account at its storage limit can always free space.
class ItemSyncEngine {
  ItemSyncEngine({
    required String appId,
    required Uint8List appKey,
    required String deviceId,
    required LocalItemStore store,
    required SyncBackend backend,
    required Ed25519KeyMaterial signingKeys,
    DateTime Function()? clock,
    Duration pullOverlap = const Duration(seconds: 30),
    int pushBatchSize = 200,
  }) : this.withCodec(
          appId: appId,
          codec: AppItemCodec(
              appId: appId, appKey: appKey, signingKeys: signingKeys),
          deviceId: deviceId,
          store: store,
          backend: backend,
          clock: clock,
          pullOverlap: pullOverlap,
          pushBatchSize: pushBatchSize,
        );

  /// An engine that seals and checks rows with [codec] instead of the
  /// account's own app key: shared spaces (`SpaceItemCodec`) use this.
  ItemSyncEngine.withCodec({
    required this.appId,
    required this.codec,
    required this.deviceId,
    required this.store,
    required this.backend,
    DateTime Function()? clock,
    this.pullOverlap = const Duration(seconds: 30),
    this.pushBatchSize = 200,
  }) : _clock = clock ?? DateTime.now;

  /// An engine for the unlocked vault's [appKey], with the signing keys
  /// derived from it.
  static Future<ItemSyncEngine> fromVault({
    required String appId,
    required Uint8List appKey,
    required String deviceId,
    required LocalItemStore store,
    required SyncBackend backend,
  }) async {
    final key = Uint8List.fromList(appKey);
    try {
      return ItemSyncEngine(
        appId: appId,
        appKey: key,
        deviceId: deviceId,
        store: store,
        backend: backend,
        signingKeys: await KeyHierarchy.signingKeys(key),
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// How far each pull reaches back before the last high-water mark. Rows
  /// committed out of order (an earlier `synced_at` landing after a later
  /// one) are caught here; re-applying a row already seen does nothing.
  final Duration pullOverlap;

  /// Rows per upload request.
  final int pushBatchSize;

  /// How far ahead of the server's time the server accepts an `updatedAt`
  /// (the `vault_items` trigger uses the same bound). A seen version further
  /// ahead than this doesn't move the logical clock, since following it would
  /// stall every later push.
  static const Duration maxClockSkew = Duration(minutes: 10);

  /// How long the server keeps tombstones (`zt_purge_tombstones`).
  static const Duration tombstoneRetention = Duration(days: 180);

  /// A device whose last pull is older than this re-syncs in full, so it
  /// can't miss a delete whose tombstone the server has since removed. A
  /// month short of [tombstoneRetention], for clock error.
  static const Duration fullResyncAfter = Duration(days: 150);

  final String appId;
  final String deviceId;
  final LocalItemStore store;
  final SyncBackend backend;

  /// Seals and opens rows: the account's app key by default.
  final ItemCodec codec;
  final DateTime Function() _clock;

  Future<void> Function()? _cancelLive;
  Future<void> _serial = Future.value();
  DateTime? _latestSeen;
  Future<void>? _clockSeed;

  /// The newest server receive time seen: a lower bound on the server's
  /// clock that doesn't depend on this device's.
  DateTime? _serverTime;
  bool _closed = false;

  /// A full re-sync ran in this engine's lifetime (stores without
  /// [PullCheckpoint] only).
  bool _fullResyncDone = false;

  /// Stops live updates and zeroes this engine's copy of the app key. Call it
  /// when the vault locks; anything still in flight then fails instead of
  /// sealing with a zeroed key.
  Future<void> close() async {
    _closed = true;
    codec.close();
    await stopLive();
  }

  void _checkOpen() {
    if (_closed) throw StateError('ItemSyncEngine is closed');
  }

  /// Create or update an item locally; [sync] pushes it.
  ///
  /// [at] overrides the edit time. Only for content that must lose to every
  /// real edit, such as an import (see `LegacyImporter`).
  Future<void> save(String itemId, Map<String, Object?> json,
          {DateTime? at}) async =>
      store.put(LocalItem(
          itemId: itemId,
          updatedAt: at?.toUtc() ?? await _stamp(),
          json: json,
          dirty: true));

  Future<void> delete(String itemId) async => store.put(LocalItem(
      itemId: itemId, updatedAt: await _stamp(), deleted: true, dirty: true));

  /// Pull and apply remote changes, then push local ones. Calls are
  /// serialised, so overlapping triggers (resume, timer, realtime) are safe.
  Future<SyncResult> sync() {
    final run = _serial.then((_) => _sync());
    _serial = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Start applying other devices' changes as they arrive.
  void startLive({void Function(SyncResult)? onApplied}) {
    _cancelLive ??= backend.subscribe(appId, (item) {
      final run = _serial.then((_) async {
        // Arrived just before close: the next unlock's pull picks it up.
        if (_closed) return const SyncResult();
        final conflicts = <SyncConflict>[];
        final rejected = <String>[];
        await codec.prepare([item]);
        final applied = await _apply(item, conflicts, rejected);
        if (rejected.isNotEmpty) {
          await store
              .setRejectedIds({...await store.rejectedIds(), item.itemId});
        }
        return SyncResult(
          applied: applied ? 1 : 0,
          conflicts: conflicts,
          rejected: rejected,
        );
      });
      // A failed live update is caught up by the next pull.
      _serial = run.then((_) {}, onError: (_) {});
      if (onApplied != null) run.then(onApplied, onError: (_) {});
    });
  }

  Future<void> stopLive() async {
    final cancel = _cancelLive;
    _cancelLive = null;
    if (cancel != null) await cancel();
  }

  Future<SyncResult> _sync() async {
    // Pull first, so a stale local edit loses here (and is reported) instead
    // of being pushed over a newer row.
    await _seedClock();
    var applied = 0;
    final conflicts = <SyncConflict>[];
    final rejected = <String>[];
    final readable = <String>{};
    var highWater = await store.lastPulledAt();
    final checkpoint = store is PullCheckpoint ? store as PullCheckpoint : null;
    // When this device last caught up. The newest row's time is only a
    // stand-in: on a vault that rarely changes it stays old however often
    // the device syncs.
    final caughtUpAt = checkpoint != null
        ? (await checkpoint.lastPullCompletedAt() ?? highWater)
        : (_fullResyncDone ? null : highWater);
    final full = caughtUpAt != null &&
        _clock().toUtc().difference(caughtUpAt.toUtc()) > fullResyncAfter;
    final since = full ? null : highWater?.subtract(pullOverlap);
    final onServer = <String>{};
    final pulled = await backend.pull(appId, since: since);
    await codec.prepare(pulled);
    for (final remote in pulled) {
      onServer.add(remote.itemId);
      if (await _apply(remote, conflicts, rejected)) applied++;
      if (!rejected.contains(remote.itemId)) readable.add(remote.itemId);
      final synced = remote.syncedAt;
      if (synced != null && (highWater == null || synced.isAfter(highWater))) {
        highWater = synced;
      }
    }
    if (full) {
      // Away longer than the server keeps tombstones: an item the server no
      // longer has was deleted elsewhere. Local edits not yet pushed stay.
      for (final local in await store.all()) {
        if (local.deleted || local.dirty || onServer.contains(local.itemId)) {
          continue;
        }
        await store.put(LocalItem(
          itemId: local.itemId,
          updatedAt: local.updatedAt,
          deleted: true,
        ));
        applied++;
      }
    }
    if (highWater != null) await store.setLastPulledAt(highWater);
    if (full) _fullResyncDone = true;
    await checkpoint?.setLastPullCompletedAt(_clock().toUtc());

    // Retry rows that failed before and weren't just pulled again.
    final retry = (await store.rejectedIds())
        .difference(readable)
        .difference(rejected.toSet());
    if (retry.isNotEmpty) {
      final again = await backend.fetch(appId, retry);
      await codec.prepare(again);
      for (final remote in again) {
        if (await _apply(remote, conflicts, rejected)) applied++;
      }
    }
    await store.setRejectedIds(rejected.toSet());

    var pushed = 0;
    var storageFull = false;
    final tooLarge = <String>[];
    final dirty = await store.dirtyItems();
    // Deletes first: the server always takes them, and they free space.
    final ordered = [
      ...dirty.where((i) => i.deleted),
      ...dirty.where((i) => !i.deleted),
    ];
    for (var i = 0; i < ordered.length; i += pushBatchSize) {
      final batch = ordered.sublist(i, min(i + pushBatchSize, ordered.length));
      final sealed = [for (final item in batch) await _seal(item)];
      Set<String> accepted;
      try {
        accepted = await backend.pushAll(appId, sealed);
      } on StorageLimitExceeded {
        // One row (or the account) is over a limit and the whole batch was
        // refused: push one at a time, so everything that fits (a delete,
        // an edit that shrinks an item) still goes up.
        accepted = {};
        for (final row in sealed) {
          try {
            accepted.addAll(await backend.pushAll(appId, [row]));
          } on StorageLimitExceeded catch (e) {
            if (e.itemTooLarge) {
              tooLarge.add(row.itemId);
            } else {
              storageFull = true;
            }
          }
        }
      }
      for (final item in batch) {
        // Not accepted: stays dirty, so the next pull reports the conflict
        // (or the push succeeds later) instead of the edit being dropped.
        if (!accepted.contains(item.itemId)) continue;
        // Leave it dirty if it was edited again while the push was in flight.
        final current = await store.get(item.itemId);
        if (current != null && current.updatedAt == item.updatedAt) {
          await store.put(current.copyWith(dirty: false));
        }
        pushed++;
      }
    }

    return SyncResult(
      pushed: pushed,
      applied: applied,
      conflicts: conflicts,
      rejected: rejected,
      storageFull: storageFull,
      tooLarge: tooLarge,
    );
  }

  /// Returns true when the remote row changed the local store.
  Future<bool> _apply(
    RemoteItem remote,
    List<SyncConflict> conflicts,
    List<String> rejected,
  ) async {
    final Map<String, Object?>? json;
    try {
      json = await _open(remote);
    } on Object {
      if (_closed) rethrow;
      if (!rejected.contains(remote.itemId)) rejected.add(remote.itemId);
      return false;
    }
    final synced = remote.syncedAt?.toUtc();
    if (synced != null &&
        (_serverTime == null || synced.isAfter(_serverTime!))) {
      _serverTime = synced;
    }
    _observe(remote.updatedAt);

    final local = await store.get(remote.itemId);
    if (local != null && !_remoteWins(remote, local)) return false;
    if (local != null && local.dirty) {
      conflicts.add(SyncConflict(itemId: local.itemId, lostLocal: local));
    }
    await store.put(LocalItem(
      itemId: remote.itemId,
      updatedAt: remote.updatedAt,
      json: json,
      deleted: remote.deleted,
    ));
    return true;
  }

  bool _remoteWins(RemoteItem remote, LocalItem local) {
    final c = remote.updatedAt.compareTo(local.updatedAt);
    if (c != 0) return c > 0;
    if (!local.dirty) return false; // same version we already have
    return remote.deviceId.compareTo(deviceId) > 0;
  }

  Future<RemoteItem> _seal(LocalItem item) async {
    _checkOpen();
    return codec.seal(item, deviceId);
  }

  /// Verifies and decrypts. Throws on any mismatch.
  Future<Map<String, Object?>?> _open(RemoteItem remote) async {
    _checkOpen();
    return codec.open(remote);
  }

  /// The next edit time: this device's clock, or just after the newest
  /// version it has seen when that is later.
  Future<DateTime> _stamp() async {
    await _seedClock();
    final wall = _clock().toUtc();
    var seen = _latestSeen;
    // A stamp from while this clock ran fast must not drag every later edit
    // past what the server accepts once the clock is corrected.
    if (seen != null && seen.isAfter(_limit())) seen = null;
    final t = seen != null && !seen.isBefore(wall)
        ? seen.add(const Duration(milliseconds: 1))
        : wall;
    _latestSeen = t;
    return t;
  }

  /// The latest `updatedAt` the server would accept now, as far as this
  /// device can tell: the later of its clock and the server time seen, plus
  /// [maxClockSkew].
  DateTime _limit() {
    final wall = _clock().toUtc();
    final server = _serverTime;
    return (server != null && server.isAfter(wall) ? server : wall)
        .add(maxClockSkew);
  }

  /// Moves the logical clock forward to [t], unless [t] is further ahead of
  /// the server than the server accepts (see [maxClockSkew]). The bound uses
  /// the later of this device's clock and the server time seen, so a device
  /// whose clock is behind still follows other devices' real edits.
  void _observe(DateTime t) {
    final u = t.toUtc();
    if (u.isAfter(_limit())) return;
    final seen = _latestSeen;
    if (seen == null || u.isAfter(seen)) _latestSeen = u;
  }

  /// After a restart, continue from the newest local version. A failed read
  /// is retried by the next call instead of being cached.
  Future<void> _seedClock() => _clockSeed ??= () async {
        try {
          _serverTime = (await store.lastPulledAt())?.toUtc();
          for (final item in await store.all()) {
            _observe(item.updatedAt);
          }
        } on Object {
          _clockSeed = null;
          rethrow;
        }
      }();
}

/// How an [ItemSyncEngine] turns local items into server rows and back.
abstract interface class ItemCodec {
  /// Seals and signs [item] for upload.
  Future<RemoteItem> seal(LocalItem item, String deviceId);

  /// Checks and decrypts [remote]; null for a tombstone. Throws when the row
  /// fails any check, so it is never applied.
  Future<Map<String, Object?>?> open(RemoteItem remote);

  /// Called with every batch of pulled rows before any of them is opened, so
  /// a codec can learn from the batch first (a shared space's member list).
  Future<void> prepare(List<RemoteItem> batch);

  /// Zeroes keys. Called when the engine closes.
  void close();
}

/// The account's own items: sealed under the app key with the item id as
/// AAD, and signed with the Ed25519 key derived from it over (app, id,
/// updatedAt, deleted, blob).
class AppItemCodec implements ItemCodec {
  AppItemCodec({
    required this.appId,
    required Uint8List appKey,
    required this.signingKeys,
  }) : _appKey = Uint8List.fromList(appKey);

  final String appId;
  final Ed25519KeyMaterial signingKeys;
  final Uint8List _appKey;

  @override
  void close() => _appKey.fillRange(0, _appKey.length, 0);

  @override
  Future<void> prepare(List<RemoteItem> batch) async {}

  @override
  Future<RemoteItem> seal(LocalItem item, String deviceId) async {
    final blob = item.deleted
        ? null
        : await SealedBox.seal(
            utf8.encode(jsonEncode(item.json)),
            _appKey,
            aad: _aad(item.itemId),
          );
    final updatedAt = item.updatedAt.toUtc();
    return RemoteItem(
      itemId: item.itemId,
      updatedAt: updatedAt,
      deviceId: deviceId,
      dataBlob: blob,
      deleted: item.deleted,
      signature: await Signing.sign(
        _signedBytes(item.itemId, updatedAt, item.deleted, blob),
        signingKeys,
      ),
    );
  }

  @override
  Future<Map<String, Object?>?> open(RemoteItem remote) async {
    final signature = remote.signature;
    if (signature == null) throw const FormatException('Unsigned row');
    final ok = await Signing.verify(
      _signedBytes(remote.itemId, remote.updatedAt.toUtc(), remote.deleted,
          remote.dataBlob),
      signature: signature,
      publicKey: signingKeys.publicKeyBytes,
    );
    if (!ok) throw const FormatException('Bad signature');
    if (remote.deleted) return null;
    final blob = remote.dataBlob;
    if (blob == null) throw const FormatException('Missing blob');
    final clear = await SealedBox.open(blob, _appKey, aad: _aad(remote.itemId));
    return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }

  List<int> _aad(String itemId) => utf8.encode('zt/item/v1|$appId|$itemId');

  List<int> _signedBytes(
    String itemId,
    DateTime updatedAt,
    bool deleted,
    Uint8List? blob,
  ) =>
      [
        ...utf8.encode(
            'zt/sig/v1|$appId|$itemId|${updatedAt.microsecondsSinceEpoch}|$deleted|'),
        ...?blob,
      ];
}
