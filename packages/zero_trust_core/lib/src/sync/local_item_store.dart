/// One item as the device keeps it: decrypted JSON plus sync bookkeeping.
class LocalItem {
  const LocalItem({
    required this.itemId,
    required this.updatedAt,
    this.json,
    this.deleted = false,
    this.dirty = false,
  });

  final String itemId;
  final DateTime updatedAt;

  /// Null on a tombstone.
  final Map<String, Object?>? json;
  final bool deleted;

  /// Changed locally and not yet pushed.
  final bool dirty;

  LocalItem copyWith({bool? dirty}) => LocalItem(
        itemId: itemId,
        updatedAt: updatedAt,
        json: json,
        deleted: deleted,
        dirty: dirty ?? this.dirty,
      );
}

/// Where an app keeps its decrypted items on the device. Apps back this with
/// their SQLCipher/Drift database; [InMemoryItemStore] is for tests and
/// prototypes.
abstract interface class LocalItemStore {
  Future<LocalItem?> get(String itemId);
  Future<List<LocalItem>> all();
  Future<void> put(LocalItem item);

  /// Items with `dirty` set. Should be an indexed query, not a scan.
  Future<List<LocalItem>> dirtyItems();

  /// High-water mark of pulled server timestamps.
  Future<DateTime?> lastPulledAt();
  Future<void> setLastPulledAt(DateTime value);

  /// Ids of remote rows that failed verification or decryption. The engine
  /// retries them on every sync, so a row that fails because of a bug is
  /// read once the bug is fixed instead of being skipped for good.
  Future<Set<String>> rejectedIds();
  Future<void> setRejectedIds(Set<String> ids);
}

class InMemoryItemStore implements LocalItemStore {
  final Map<String, LocalItem> _items = {};
  DateTime? _lastPulled;
  Set<String> _rejected = {};

  @override
  Future<LocalItem?> get(String itemId) async => _items[itemId];

  @override
  Future<List<LocalItem>> all() async => _items.values.toList();

  @override
  Future<void> put(LocalItem item) async => _items[item.itemId] = item;

  @override
  Future<List<LocalItem>> dirtyItems() async =>
      _items.values.where((i) => i.dirty).toList();

  @override
  Future<DateTime?> lastPulledAt() async => _lastPulled;

  @override
  Future<void> setLastPulledAt(DateTime value) async => _lastPulled = value;

  @override
  Future<Set<String>> rejectedIds() async => {..._rejected};

  @override
  Future<void> setRejectedIds(Set<String> ids) async => _rejected = {...ids};
}
