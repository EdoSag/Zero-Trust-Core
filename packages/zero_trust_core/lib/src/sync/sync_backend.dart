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

/// The server refused a write because of the account's storage limits
/// (`zt_storage_usage`, core 0.9). Deletes are never refused, so the user
/// can always free space.
class StorageLimitExceeded implements Exception {
  const StorageLimitExceeded({this.itemTooLarge = false});

  /// One item is bigger than the per-item cap (1 MiB sealed) rather than the
  /// account being full. That item can't sync until it is made smaller.
  final bool itemTooLarge;

  @override
  String toString() => itemTooLarge
      ? 'StorageLimitExceeded(item too large)'
      : 'StorageLimitExceeded(storage full)';
}

/// Server side of per-item sync. Supabase in production; in-memory in tests.
abstract interface class SyncBackend {
  /// Rows of [app] the server received after [since] (all when null),
  /// ordered by `synced_at`.
  Future<List<RemoteItem>> pull(String app, {DateTime? since});

  /// The current rows for [itemIds] (missing ids are left out).
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds);

  /// Writes [items] in one request and returns the ids the server accepted.
  /// A missing id means the server kept its row instead: a newer one
  /// (another device wrote after this one last pulled; the next pull reports
  /// the conflict) or a write dated too far in the future (it is accepted
  /// once the writing device's time is no longer ahead of the server's).
  ///
  /// Throws [StorageLimitExceeded] when the server refuses the batch for the
  /// account's storage limits; nothing in the batch is written then.
  Future<Set<String>> pushAll(String app, List<RemoteItem> items);

  /// Live changes from other devices. Returns a cancel function.
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange);
}
