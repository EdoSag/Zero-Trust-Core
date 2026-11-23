import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:zt_crypto/zt_crypto.dart';

import '../platform/zt_platform.dart';

import 'legacy_importer.dart';
import 'local_item_store.dart';

/// The store's file can't be opened with this key: it is damaged, or was
/// written under another key.
class LocalStoreUnreadable implements Exception {
  const LocalStoreUnreadable(this.path);
  final String path;
  @override
  String toString() => 'LocalStoreUnreadable($path)';
}

/// The shared on-device store: a SQLite database encrypted as a whole file
/// (SQLite3 Multiple Ciphers, ChaCha20-Poly1305) under a key derived from the
/// app key. Items, ids, timestamps and sync state are all inside the
/// encrypted file, and nothing is readable while the vault is locked.
///
/// Every app must select the cipher build in its own `pubspec.yaml`:
///
/// ```yaml
/// hooks:
///   user_defines:
///     sqlite3:
///       source: sqlite3mc
/// ```
///
/// Without it [open] throws rather than writing plain text.
///
/// On the web the same encrypted file lives in the browser's IndexedDB
/// (SQLite3 Multiple Ciphers as WebAssembly; the app ships
/// `web/sqlite3mc.wasm`), so the browser only ever stores ciphertext.
///
/// Calls run on the calling isolate. That is fine for the item counts these
/// apps keep; move the database to a background isolate if a list grows into
/// the tens of thousands.
class ZtLocalStore
    implements LocalItemStore, LegacyImportLedger, PullCheckpoint {
  ZtLocalStore._(this._handle, this._mergeBursts);

  final ZtDatabaseHandle _handle;
  CommonDatabase get _db => _handle.db;
  final _changes = StreamController<Set<String>>.broadcast();
  bool _closed = false;

  /// Whether a long run of writes is announced in batches (see [changes]).
  final bool _mergeBursts;
  final Stopwatch _clock = Stopwatch()..start();
  final Set<String> _held = {};
  Timer? _burstTimer;
  int _lastWrite = 0;
  int _run = 0;
  bool _wroteSinceTick = false;

  /// Writes closer together than this belong to one run.
  static const _burstGap = Duration(milliseconds: 50);

  /// This many writes in one run make it a burst: an import or a large
  /// sync, not a screen saving a few items.
  static const _burstSize = 24;

  /// How often a burst's changes are announced.
  static const _burstInterval = Duration(milliseconds: 120);

  static const _schemaVersion = 1;

  /// Opens (creating if needed) the store at [path], or an in-memory one
  /// when [path] is null. Throws [LocalStoreUnreadable] when the file exists
  /// but [appKey] doesn't open it.
  ///
  /// [mergeBursts] is whether a long run of writes is announced on [changes]
  /// in batches. On by default, except under `flutter test`, whose fake
  /// clock never fires the timer that ends a batch.
  static Future<ZtLocalStore> open({
    required Uint8List appKey,
    String? path,
    bool? mergeBursts,
  }) async {
    // Copy first: the vault zeroes its key on lock, maybe mid-open.
    final copy = Uint8List.fromList(appKey);
    final key = await Kdf.hkdf(copy, 'zt/localdb/v1');
    copy.fillRange(0, copy.length, 0);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    key.fillRange(0, key.length, 0);

    final handle = await ztOpenDatabase(path);
    final db = handle.db;
    try {
      if (db.select('pragma cipher').isEmpty) {
        throw StateError(
          'ZtLocalStore needs the encrypted SQLite build. Add to the app '
          "pubspec.yaml: hooks: user_defines: sqlite3: source: sqlite3mc",
        );
      }
      // An in-memory store never touches the disk, so it has no file key.
      if (path != null) {
        db.execute("pragma hexkey = '$hex'");
        try {
          db.select('select count(*) from sqlite_master');
        } on SqliteException {
          throw LocalStoreUnreadable(path);
        }
        if (handle.supportsWal) db.execute('pragma journal_mode = wal');
      }
      _migrate(db);
      return ZtLocalStore._(handle, mergeBursts ?? !ztInFlutterTest);
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  static void _migrate(CommonDatabase db) {
    final version = db.userVersion;
    if (version > _schemaVersion) {
      throw StateError('Local store schema $version is newer than this app');
    }
    if (version < 1) {
      db.execute('''
        create table items (
          item_id text primary key,
          updated_at integer not null,
          deleted integer not null default 0,
          dirty integer not null default 0,
          json text
        ) strict;
        create index items_dirty on items (item_id) where dirty = 1;
        create table meta (key text primary key, value text not null) strict;
      ''');
    }
    db.userVersion = _schemaVersion;
  }

  /// Where an app keeps the store for [userId]. One file per account, so a
  /// second account on the same device never sees or reuses the first's.
  static Future<String> pathFor({
    required String appId,
    required String userId,
  }) =>
      ztDatabasePath('zt_${appId}_$userId.db');

  /// Deletes a closed store's files, for example after account deletion.
  static Future<void> deleteFiles(String path) => ztDeleteDatabase(path);

  /// Renames a store that can't be opened to `<path>.unreadable-<time>`, so
  /// a fresh store can take its place without destroying what might still
  /// be recovered. Earlier set-aside copies are never replaced. (On the web,
  /// which can't rename, the unreadable store is deleted.)
  static Future<void> moveAside(String path) => ztMoveDatabaseAside(path);

  /// Ids of items that changed, after each write. For refreshing lists.
  ///
  /// A long run of writes (an import, or a sync that brings hundreds of
  /// items) is announced in batches a fraction of a second apart instead of
  /// once per item, so a list that reloads on every event isn't rebuilt
  /// hundreds of times in a row.
  Stream<Set<String>> get changes => _changes.stream;

  void _changed(String itemId) {
    if (!_mergeBursts) {
      _changes.add({itemId});
      return;
    }
    final now = _clock.elapsedMicroseconds;
    _run = now - _lastWrite <= _burstGap.inMicroseconds ? _run + 1 : 1;
    _lastWrite = now;
    if (_burstTimer == null && _run < _burstSize) {
      _changes.add({itemId});
      return;
    }
    _held.add(itemId);
    _wroteSinceTick = true;
    _burstTimer ??= Timer.periodic(_burstInterval, (timer) {
      _flushHeld();
      // A tick with no write since the last one: the burst is over.
      if (!_wroteSinceTick) {
        timer.cancel();
        _burstTimer = null;
        _run = 0;
      }
      _wroteSinceTick = false;
    });
  }

  void _flushHeld() {
    if (_held.isEmpty || _closed) return;
    final ids = Set.of(_held);
    _held.clear();
    _changes.add(ids);
  }

  /// Items that aren't deleted, for showing in the app.
  Future<List<LocalItem>> liveItems() async =>
      _query('select * from items where deleted = 0');

  /// Closes the database. The store can't be used afterwards.
  Future<void> close() async {
    if (_closed) return;
    _burstTimer?.cancel();
    _burstTimer = null;
    _flushHeld();
    _closed = true;
    await _handle.close();
    await _changes.close();
  }

  @override
  Future<LocalItem?> get(String itemId) async {
    final rows = _query('select * from items where item_id = ?', [itemId]);
    return rows.isEmpty ? null : rows.single;
  }

  @override
  Future<List<LocalItem>> all() async => _query('select * from items');

  @override
  Future<List<LocalItem>> dirtyItems() async =>
      _query('select * from items where dirty = 1');

  @override
  Future<void> put(LocalItem item) async {
    _db.execute(
      'insert or replace into items '
      '(item_id, updated_at, deleted, dirty, json) values (?, ?, ?, ?, ?)',
      [
        item.itemId,
        item.updatedAt.toUtc().microsecondsSinceEpoch,
        item.deleted ? 1 : 0,
        item.dirty ? 1 : 0,
        item.json == null ? null : jsonEncode(item.json),
      ],
    );
    _changed(item.itemId);
  }

  @override
  Future<DateTime?> lastPulledAt() async {
    final v = _meta('last_pulled_at');
    return v == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(int.parse(v), isUtc: true);
  }

  @override
  Future<void> setLastPulledAt(DateTime value) async =>
      _setMeta('last_pulled_at', '${value.toUtc().microsecondsSinceEpoch}');

  @override
  Future<DateTime?> lastPullCompletedAt() async {
    final v = _meta('last_pull_completed_at');
    return v == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(int.parse(v), isUtc: true);
  }

  @override
  Future<void> setLastPullCompletedAt(DateTime value) async => _setMeta(
      'last_pull_completed_at', '${value.toUtc().microsecondsSinceEpoch}');

  @override
  Future<Set<String>> rejectedIds() async {
    final v = _meta('rejected_ids');
    return v == null ? {} : (jsonDecode(v) as List).cast<String>().toSet();
  }

  @override
  Future<void> setRejectedIds(Set<String> ids) async =>
      _setMeta('rejected_ids', jsonEncode(ids.toList()..sort()));

  @override
  Future<bool> legacyImportDone(String source) async =>
      _meta('legacy_import:$source') != null;

  @override
  Future<void> markLegacyImportDone(String source) async => _setMeta(
      'legacy_import:$source', DateTime.now().toUtc().toIso8601String());

  List<LocalItem> _query(String sql, [List<Object?> args = const []]) => [
        for (final row in _db.select(sql, args))
          LocalItem(
            itemId: row['item_id'] as String,
            updatedAt: DateTime.fromMicrosecondsSinceEpoch(
                _int(row['updated_at']),
                isUtc: true),
            deleted: _int(row['deleted']) == 1,
            dirty: _int(row['dirty']) == 1,
            json: switch (row['json']) {
              final String s => (jsonDecode(s) as Map).cast<String, Object?>(),
              _ => null,
            },
          ),
      ];

  /// The web build may hand 64-bit integers back as [BigInt].
  static int _int(Object? v) => v is BigInt ? v.toInt() : v as int;

  String? _meta(String key) {
    final rows = _db.select('select value from meta where key = ?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void _setMeta(String key, String value) => _db.execute(
      'insert or replace into meta (key, value) values (?, ?)', [key, value]);
}
