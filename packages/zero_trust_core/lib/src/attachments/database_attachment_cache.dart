import 'dart:typed_data';

import '../platform/zt_platform.dart';
import 'attachment_cache.dart';

/// [AttachmentCache] in one SQLite file per app and account. Used on the
/// web, where it lives in the browser's IndexedDB, so attachments added
/// offline (and their waiting uploads and deletes) survive a lock, a reload
/// or closing the tab. Holds sealed files only, like the file cache.
class DatabaseAttachmentCache implements AttachmentCache {
  DatabaseAttachmentCache._(this._handle);

  final ZtDatabaseHandle _handle;
  bool _closed = false;

  static String fileName(String appId, String userId) =>
      'zt_attachments_${appId}_$userId.db';

  /// Opens (creating if needed) the cache at [path], or in memory if null.
  static Future<DatabaseAttachmentCache> open([String? path]) async {
    final handle = await ztOpenDatabase(path);
    try {
      handle.db.execute('''
        create table if not exists files (
          id text primary key,
          data blob not null
        ) strict;
        create table if not exists pending (
          kind text not null,
          id text not null,
          primary key (kind, id)
        ) strict;
      ''');
      return DatabaseAttachmentCache._(handle);
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  static Future<DatabaseAttachmentCache> forAccount({
    required String appId,
    required String userId,
  }) async =>
      open(await ztDatabasePath(fileName(appId, userId)));

  /// Deletes the closed cache, for example after account deletion.
  static Future<void> deleteFor({
    required String appId,
    required String userId,
  }) async =>
      ztDeleteDatabase(await ztDatabasePath(fileName(appId, userId)));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.close();
  }

  @override
  Future<Uint8List?> read(String id) async {
    final rows = _handle.db.select('select data from files where id = ?', [id]);
    return rows.isEmpty ? null : rows.single['data'] as Uint8List;
  }

  @override
  Future<void> write(String id, Uint8List sealed) async => _handle.db.execute(
      'insert or replace into files (id, data) values (?, ?)', [id, sealed]);

  @override
  Future<void> remove(String id) async =>
      _handle.db.execute('delete from files where id = ?', [id]);

  Set<String> _pending(String kind) => {
        for (final row in _handle.db
            .select('select id from pending where kind = ?', [kind]))
          row['id'] as String,
      };

  void _setPending(String kind, Set<String> ids) {
    final db = _handle.db;
    db.execute('begin');
    try {
      db.execute('delete from pending where kind = ?', [kind]);
      for (final id in ids) {
        db.execute('insert into pending (kind, id) values (?, ?)', [kind, id]);
      }
      db.execute('commit');
    } catch (_) {
      db.execute('rollback');
      rethrow;
    }
  }

  @override
  Future<Set<String>> pendingUploads() async => _pending('upload');

  @override
  Future<Set<String>> pendingDeletes() async => _pending('delete');

  @override
  Future<void> setPendingUploads(Set<String> ids) async =>
      _setPending('upload', ids);

  @override
  Future<void> setPendingDeletes(Set<String> ids) async =>
      _setPending('delete', ids);
}
