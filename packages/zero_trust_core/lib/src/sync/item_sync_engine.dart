import 'dart:async';
import 'dart:convert';
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

  /// Item ids whose rows failed signature or decryption checks. Never
  /// applied: a server or attacker cannot inject or swap data.
  final List<String> rejected;
}

/// Encrypted per-item sync over the shared `vault_items` table, for any app.
///
/// - Every item is sealed under the app key with the item id as AAD, and
///   signed with the user's Ed25519 key over (app, id, updatedAt, deleted,
///   blob), so the server only ever stores opaque, tamper-evident rows.
/// - Conflicts resolve last-writer-wins on `updatedAt` (device id breaks
///   ties); a losing local edit is reported in [SyncResult.conflicts].
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
  })  : _appKey = appKey,
        _clock = clock ?? DateTime.now;

  final String appId;
  final String deviceId;
  final LocalItemStore store;
  final SyncBackend backend;
  final Ed25519KeyMaterial signingKeys;
  final Uint8List _appKey;
  final DateTime Function() _clock;

  Future<void> Function()? _cancelLive;
  Future<void> _serial = Future.value();

  /// Create or update an item locally; [sync] pushes it.
  Future<void> save(String itemId, Map<String, Object?> json) => store.put(
        LocalItem(itemId: itemId, updatedAt: _now(), json: json, dirty: true),
      );

  Future<void> delete(String itemId) => store.put(
        LocalItem(
            itemId: itemId, updatedAt: _now(), deleted: true, dirty: true),
      );

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
        final conflicts = <SyncConflict>[];
        final rejected = <String>[];
        final applied = await _apply(item, conflicts, rejected);
        return SyncResult(
          applied: applied ? 1 : 0,
          conflicts: conflicts,
          rejected: rejected,
        );
      });
      _serial = run.then((_) {}, onError: (_) {});
      if (onApplied != null) run.then(onApplied);
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
    var applied = 0;
    final conflicts = <SyncConflict>[];
    final rejected = <String>[];
    var highWater = await store.lastPulledAt();
    for (final remote in await backend.pull(appId, since: highWater)) {
      if (await _apply(remote, conflicts, rejected)) applied++;
      final synced = remote.syncedAt;
      if (synced != null && (highWater == null || synced.isAfter(highWater))) {
        highWater = synced;
      }
    }
    if (highWater != null) await store.setLastPulledAt(highWater);

    var pushed = 0;
    for (final item in await store.all()) {
      if (!item.dirty) continue;
      await backend.push(appId, await _seal(item));
      // Leave it dirty if it was edited again while the push was in flight.
      final current = await store.get(item.itemId);
      if (current != null && current.updatedAt == item.updatedAt) {
        await store.put(current.copyWith(dirty: false));
      }
      pushed++;
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
      rejected.add(remote.itemId);
      return false;
    }

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

  DateTime _now() => _clock().toUtc();
}
