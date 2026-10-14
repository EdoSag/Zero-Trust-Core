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

  /// High-water mark of pulled server timestamps.
  Future<DateTime?> lastPulledAt();
  Future<void> setLastPulledAt(DateTime value);
}

class InMemoryItemStore implements LocalItemStore {
  final Map<String, LocalItem> _items = {};
  DateTime? _lastPulled;

  @override
  Future<LocalItem?> get(String itemId) async => _items[itemId];

  @override
  Future<List<LocalItem>> all() async => _items.values.toList();

  @override
  Future<void> put(LocalItem item) async => _items[item.itemId] = item;

  @override
  Future<DateTime?> lastPulledAt() async => _lastPulled;

  @override
  Future<void> setLastPulledAt(DateTime value) async => _lastPulled = value;
}
