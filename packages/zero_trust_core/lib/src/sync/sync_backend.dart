import 'dart:typed_data';

/// One `vault_items` row as it travels: opaque to the server.
class RemoteItem {
  const RemoteItem({
    required this.itemId,
    required this.updatedAt,
    required this.deviceId,
    this.dataBlob,
    this.signature,
    this.deleted = false,
    this.syncedAt,
  });

  final String itemId;

  /// When the writing device changed the item. Decides last-writer-wins.
  final DateTime updatedAt;

  /// Server receive time (set by a trigger, never by clients). Pulls page on
  /// this, so a device with a slow clock can't hide its writes.
  final DateTime? syncedAt;
  final String deviceId;

  /// Sealed box under the app key. Null on a tombstone.
  final Uint8List? dataBlob;

  /// Ed25519 over the row's identity and content (see `ItemSyncEngine`), so
  /// the server cannot forge rows or swap one item's blob into another.
  final Uint8List? signature;
  final bool deleted;
}

/// Server side of per-item sync. Supabase in production; in-memory in tests.
abstract interface class SyncBackend {
  /// Rows of [app] the server received after [since] (all when null),
  /// ordered by `synced_at`.
  Future<List<RemoteItem>> pull(String app, {DateTime? since});

  Future<void> push(String app, RemoteItem item);

  /// Live changes from other devices. Returns a cancel function.
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange);
}
