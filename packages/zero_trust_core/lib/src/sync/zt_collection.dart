import 'dart:async';

import 'local_item_store.dart';
import 'sync_providers.dart';
import 'zt_local_store.dart';

/// An item written by a newer version of the app than this one: its
/// [ZtCollection.version] is higher than the collection's. It is kept,
/// synced and shown as "update the app to see it", never overwritten.
class ZtNewerItem {
  const ZtNewerItem({required this.itemId, required this.version});
  final String itemId;
  final int version;
}

/// Thrown by [ZtCollection.save] instead of overwriting an item that a newer
/// app version wrote; saving it with this version's fields would drop the
/// newer ones on every device.
class ItemFromNewerVersion implements Exception {
  const ItemFromNewerVersion(this.itemId, this.version);
  final String itemId;
  final int version;
  @override
  String toString() =>
      'ItemFromNewerVersion($itemId is version $version, update the app)';
}

/// One kind of item an app keeps in its synced store: notes, notebooks,
/// tasks, lists, workouts, contacts, labels. Several collections share one
/// app's store; each item's JSON says which one it belongs to.
///
/// Two reserved JSON keys, written by the collection, never by the app:
///
/// - `kind`: the collection's [kind]. One collection per app may have a null
///   kind and owns every item without one. That keeps items written before
///   collections existed readable (Notes' notes never had a `kind`).
/// - `_v`: the schema version the item was written with, absent meaning 1.
///   Older items are passed through [upgrade] when read. Items from a newer
///   app version are listed by [newerItems] and never overwritten.
///
/// Saving keeps keys this version doesn't know about (a field a newer
/// version added at the same schema version), so an older app doesn't strip
/// them. [toJson] must therefore write every field it owns, with null for a
/// cleared optional field, rather than leaving the key out.
class ZtCollection<T> {
  const ZtCollection({
    required this.kind,
    required this.fromJson,
    required this.toJson,
    required this.idOf,
    this.version = 1,
    this.upgrade,
  }) : assert(version >= 1);

  /// The value of the item's `kind` key, or null for the app's default
  /// collection (items with no `kind`).
  final String? kind;

  /// The schema version this app writes.
  final int version;

  /// Builds a value from an item's JSON at [version] (after [upgrade]).
  /// `updatedAt` is the item's last edit time from sync.
  final T Function(String id, Map<String, Object?> json, DateTime updatedAt)
      fromJson;

  /// The value's own fields. `kind` and `_v` are added by the collection.
  final Map<String, Object?> Function(T value) toJson;

  final String Function(T value) idOf;

  /// Brings JSON written at an older schema version [from] up to [version].
  /// Called with each older item on read; the item is rewritten only when
  /// the app next saves it.
  final Map<String, Object?> Function(Map<String, Object?> json, int from)?
      upgrade;

  static const kindKey = 'kind';
  static const versionKey = '_v';

  /// Whether this collection owns an item with [json].
  bool owns(Map<String, Object?>? json) =>
      json != null && json[kindKey] == kind;

  /// The schema version [json] was written with.
  static int versionOf(Map<String, Object?> json) => switch (json[versionKey]) {
        final int v when v >= 1 => v,
        _ => 1,
      };

  /// The value of a live [item] this collection owns, or null for a
  /// tombstone, another collection's item, or an item from a newer version.
  T? decode(LocalItem item) {
    final json = item.json;
    if (item.deleted || !owns(json)) return null;
    final v = versionOf(json!);
    if (v > version) return null;
    var data = Map<String, Object?>.of(json);
    if (v < version) {
      final up = upgrade;
      if (up == null) {
        throw StateError('$kind items at version $v need an upgrade function');
      }
      data = up(data, v);
    }
    return fromJson(item.itemId, data, item.updatedAt);
  }

  /// The JSON stored for [value], keeping keys from [previous] (the item as
  /// stored now) that this version doesn't write.
  Map<String, Object?> encode(T value, {Map<String, Object?>? previous}) => {
        if (previous != null && versionOf(previous) == version) ...previous,
        ...toJson(value),
        kindKey: kind,
        versionKey: version,
      }..removeWhere((k, v) => k == kindKey && v == null);

  /// Every live value in [store], in no particular order.
  Future<List<T>> list(LocalItemStore store) async => [
        for (final item in await store.all())
          if (decode(item) case final T value) value,
      ];

  Future<T?> get(LocalItemStore store, String id) async {
    final item = await store.get(id);
    return item == null ? null : decode(item);
  }

  /// Items of this collection from a newer app version, which this version
  /// can't show. The app should say "Update the app to see N items".
  Future<List<ZtNewerItem>> newerItems(LocalItemStore store) async => [
        for (final item in await store.all())
          if (!item.deleted && owns(item.json))
            if (versionOf(item.json!) case final v when v > version)
              ZtNewerItem(itemId: item.itemId, version: v),
      ];

  /// The live values now and again after every change to [store].
  Stream<List<T>> watch(ZtLocalStore store) {
    late final StreamController<List<T>> controller;
    StreamSubscription<Set<String>>? changes;
    var closed = false;
    Future<void> emit() async {
      try {
        final values = await list(store);
        if (!closed) controller.add(values);
      } on Object catch (e, s) {
        if (!closed) controller.addError(e, s);
      }
    }

    controller = StreamController<List<T>>(
      onListen: () {
        changes = store.changes.listen((_) => emit());
        emit();
      },
      onCancel: () async {
        closed = true;
        await changes?.cancel();
      },
    );
    return controller.stream;
  }

  /// Saves [value] through [sync] so it is pushed to the account's other
  /// devices. Throws [ItemFromNewerVersion] rather than overwrite an item a
  /// newer app version wrote.
  Future<void> save(SyncController sync, LocalItemStore store, T value) async {
    final id = idOf(value);
    final previous = (await store.get(id))?.json;
    if (previous != null && owns(previous)) {
      final v = versionOf(previous);
      if (v > version) throw ItemFromNewerVersion(id, v);
    }
    await sync.save(
        id,
        encode(value,
            previous: previous != null && owns(previous) ? previous : null));
  }

  /// Deletes the item with [id] on every device.
  Future<void> delete(SyncController sync, String id) => sync.delete(id);
}
