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
/// - Deletes are tombstones, so they reach every device.
class ItemSyncEngine {
  ItemSyncEngine({
    required this.appId,
    required Uint8List appKey,
    required this.deviceId,
    required this.store,
    required this.backend,
    required this.signingKeys,
    DateTime Function()? clock,
    this.pullOverlap = const Duration(seconds: 30),
    this.pushBatchSize = 200,
  })  : _appKey = Uint8List.fromList(appKey),
        _clock = clock ?? DateTime.now;

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

  final String appId;
  final String deviceId;
  final LocalItemStore store;
  final SyncBackend backend;
  final Ed25519KeyMaterial signingKeys;
  final Uint8List _appKey;
  final DateTime Function() _clock;

  Future<void> Function()? _cancelLive;
  Future<void> _serial = Future.value();
  DateTime? _latestSeen;
  Future<void>? _clockSeed;

  /// The newest server receive time seen: a lower bound on the server's
  /// clock that doesn't depend on this device's.
  DateTime? _serverTime;
  bool _closed = false;

  /// Stops live updates and zeroes this engine's copy of the app key. Call it
  /// when the vault locks; anything still in flight then fails instead of
  /// sealing with a zeroed key.
  Future<void> close() async {
    _closed = true;
    _appKey.fillRange(0, _appKey.length, 0);
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
    final since = highWater?.subtract(pullOverlap);
    for (final remote in await backend.pull(appId, since: since)) {
      if (await _apply(remote, conflicts, rejected)) applied++;
      if (!rejected.contains(remote.itemId)) readable.add(remote.itemId);
      final synced = remote.syncedAt;
      if (synced != null && (highWater == null || synced.isAfter(highWater))) {
        highWater = synced;
      }
    }
    if (highWater != null) await store.setLastPulledAt(highWater);

    // Retry rows that failed before and weren't just pulled again.
    final retry = (await store.rejectedIds())
        .difference(readable)
        .difference(rejected.toSet());
    if (retry.isNotEmpty) {
      for (final remote in await backend.fetch(appId, retry)) {
        if (await _apply(remote, conflicts, rejected)) applied++;
      }
    }
    await store.setRejectedIds(rejected.toSet());

    var pushed = 0;
    final dirty = await store.dirtyItems();
    for (var i = 0; i < dirty.length; i += pushBatchSize) {
      final batch = dirty.sublist(i, min(i + pushBatchSize, dirty.length));
      final sealed = [for (final item in batch) await _seal(item)];
      final accepted = await backend.pushAll(appId, sealed);
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

  /// Verifies the signature and decrypts. Throws on any mismatch.
  Future<Map<String, Object?>?> _open(RemoteItem remote) async {
    _checkOpen();
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
