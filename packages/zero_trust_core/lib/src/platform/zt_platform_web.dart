import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import 'zt_database.dart';

/// Where the web build loads the encrypted SQLite (SQLite3 Multiple Ciphers
/// compiled to WebAssembly), relative to the page. Each web app ships the
/// file in its `web/` folder; see `tool/fetch_sqlite3mc_wasm.sh` in the
/// core repository, which pins the version and checksum.
String ztSqliteWasmUrl = 'sqlite3mc.wasm';

const _idbName = 'zt_local_store';

Future<WasmSqlite3>? _loaded;

Future<WasmSqlite3> _load() => _loaded ??= () async {
      final sqlite = await WasmSqlite3.loadFromUrlString(ztSqliteWasmUrl);
      // Only for in-memory databases (tests, previews); nothing touches it.
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
      return sqlite;
    }();

var _vfsCount = 0;

/// Takes the browser-wide lock for [path] (Web Locks API, shared by every
/// tab of this site), or throws [LocalStoreInUse] when another tab holds
/// it. Returns the function that releases it, which completes once the
/// browser has actually let go (so this tab can take it again at once).
Future<Future<void> Function()> _lock(String path) async {
  final granted = Completer<bool>();
  final release = Completer<void>();
  JSPromise<JSAny?> onGrant(web.Lock? lock) {
    granted.complete(lock != null);
    // The lock is held until this promise settles.
    return (lock == null ? Future<JSAny?>.value() : release.future.then((_) {}))
        .then((_) => null)
        .toJS;
  }

  final done = web.window.navigator.locks
      .request(
        'zt-store:$path',
        web.LockOptions(ifAvailable: true),
        onGrant.toJS,
      )
      .toDart;
  if (!await granted.future) throw LocalStoreInUse(path);
  return () async {
    if (!release.isCompleted) release.complete();
    await done;
  };
}

/// IndexedDB, read fresh: the file system keeps its own copy of the files
/// from the moment it opens, so each holder of the lock opens a new one and
/// sees what the previous holder (maybe another tab) wrote.
Future<(WasmSqlite3, IndexedDbFileSystem, String)> _freshFs() async {
  final sqlite = await _load();
  final name = 'zt-idb-${_vfsCount++}';
  final fs = await IndexedDbFileSystem.open(dbName: _idbName, vfsName: name);
  sqlite.registerVirtualFileSystem(fs);
  return (sqlite, fs, name);
}

Future<void> _closeFs(WasmSqlite3 sqlite, IndexedDbFileSystem fs) async {
  // Writes reach IndexedDB in the background; wait for them before letting
  // another tab in, or before the page goes away after a lock or sign-out.
  await fs.flush();
  sqlite.unregisterVirtualFileSystem(fs);
  await fs.close();
}

/// Opens the database at [path] inside the browser's IndexedDB, or an
/// in-memory one when null. With a key set (`pragma hexkey`), SQLite3
/// Multiple Ciphers encrypts every page before it reaches IndexedDB,
/// exactly like the file on a phone. Throws [LocalStoreInUse] while another
/// tab has it open.
Future<ZtDatabaseHandle> ztOpenDatabase(String? path) async {
  if (path == null) {
    final db = (await _load()).openInMemory();
    return ZtDatabaseHandle(db, () async => db.close(), supportsWal: false);
  }
  final unlock = await _lock(path);
  try {
    final (sqlite, fs, vfs) = await _freshFs();
    try {
      // SQLite3 Multiple Ciphers wraps every registered file system;
      // opening through the wrapper is what makes a key apply.
      final db = sqlite.open(path, vfs: 'multipleciphers-$vfs');
      return ZtDatabaseHandle(db, () async {
        try {
          db.close();
          await _closeFs(sqlite, fs);
        } finally {
          await unlock();
        }
      }, supportsWal: false);
    } catch (_) {
      await _closeFs(sqlite, fs);
      rethrow;
    }
  } catch (_) {
    await unlock();
    rethrow;
  }
}

Future<String> ztDatabasePath(String fileName) async => '/$fileName';

const _suffixes = ['', '-journal', '-wal', '-shm'];

/// Deletes the closed database at [path]. Throws [LocalStoreInUse] while
/// another tab has it open.
Future<void> ztDeleteDatabase(String path) async {
  final unlock = await _lock(path);
  try {
    final (sqlite, fs, _) = await _freshFs();
    for (final suffix in _suffixes) {
      if (fs.xAccess('$path$suffix', 0) != 0) fs.xDelete('$path$suffix', 0);
    }
    await _closeFs(sqlite, fs);
  } finally {
    await unlock();
  }
}

/// The browser's file system can't rename, so an unreadable store is
/// deleted instead. It is only a cache: a fresh one syncs everything down
/// again. Edits that never reached the server can't be read either way.
Future<void> ztMoveDatabaseAside(String path) => ztDeleteDatabase(path);

/// Saves [bytes] as a download named [fileName].
Future<void> ztDownloadFile(String fileName, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before freeing it.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
