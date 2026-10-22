import 'package:zero_trust_core/zero_trust_core.dart';

/// In-memory `vault_items`: one row per (app, item), stamped with a server
/// receive time like the `synced_at` trigger does.
class FakeSyncBackend implements SyncBackend {
  final Map<String, RemoteItem> rows = {};
  final List<void Function(RemoteItem)> _listeners = [];
  int _tick = 0;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    final out = rows.entries
        .where((e) => e.key.startsWith('$app/'))
        .map((e) => e.value)
        .where((r) => since == null || r.syncedAt!.isAfter(since))
        .where((r) => !uncommitted.contains(r.itemId))
        .toList()
      ..sort((a, b) => a.syncedAt!.compareTo(b.syncedAt!));
    return out;
  }

  /// Runs before each push lands, to interleave another device's write.
  Future<void> Function()? beforePush;

  /// The server's clock, for the far-future guard.
  DateTime Function() serverNow = () => DateTime.utc(2026, 10, 11, 12);

  /// Off: a server from before the far-future guard existed.
  bool guardFuture = true;

  /// Rows per [pushAll] call, to check batching.
  final List<int> pushBatches = [];

  /// Rows hidden from [pull] until released, like a transaction that
  /// committed after a later one.
  final Set<String> uncommitted = {};

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) async => [
        for (final id in itemIds)
          if (rows['$app/$id'] case final row?) row,
      ];

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    pushBatches.add(items.length);
    final hook = beforePush;
    beforePush = null;
    if (hook != null) await hook();
    final accepted = <String>{};
    for (final item in items) {
      // Mirrors the vault_items trigger: an older write never replaces a
      // newer row, and a write dated far ahead of the server is skipped.
      final existing = rows['$app/${item.itemId}'];
      if (existing != null && item.updatedAt.isBefore(existing.updatedAt)) {
        continue;
      }
      if (guardFuture &&
          item.updatedAt
              .isAfter(serverNow().add(ItemSyncEngine.maxClockSkew))) {
        continue;
      }
      final stored = _withSyncedAt(item);
      rows['$app/${item.itemId}'] = stored;
      accepted.add(item.itemId);
      for (final l in List.of(_listeners)) {
        l(stored);
      }
    }
    return accepted;
  }

  /// Writes a row as a hostile server or another user could.
  void inject(String app, RemoteItem item) =>
      rows['$app/${item.itemId}'] = _withSyncedAt(item);

  RemoteItem _withSyncedAt(RemoteItem item, {DateTime? syncedAt}) => RemoteItem(
        itemId: item.itemId,
        updatedAt: item.updatedAt,
        deviceId: item.deviceId,
        dataBlob: item.dataBlob,
        signature: item.signature,
        deleted: item.deleted,
        syncedAt: syncedAt ?? serverNow().add(Duration(milliseconds: ++_tick)),
      );

  /// Re-stamps a row's server receive time, as a transaction that started
  /// earlier (and so got an earlier `synced_at`) would leave it.
  void backdate(String app, String itemId, Duration by) {
    final row = rows['$app/$itemId']!;
    rows['$app/$itemId'] =
        _withSyncedAt(row, syncedAt: row.syncedAt!.subtract(by));
  }

  @override
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange) {
    _listeners.add(onChange);
    return () async => _listeners.remove(onChange);
  }
}
