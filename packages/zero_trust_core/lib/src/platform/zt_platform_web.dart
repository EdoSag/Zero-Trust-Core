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

const _vfsName = 'zt-indexeddb';

Future<(WasmSqlite3, IndexedDbFileSystem)>? _loaded;

Future<(WasmSqlite3, IndexedDbFileSystem)> _load() => _loaded ??= () async {
      final sqlite = await WasmSqlite3.loadFromUrlString(ztSqliteWasmUrl);
      // Only for in-memory databases (tests, previews); nothing touches it.
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
      final fs = await IndexedDbFileSystem.open(
          dbName: 'zt_local_store', vfsName: _vfsName);
      sqlite.registerVirtualFileSystem(fs);
      return (sqlite, fs);
    }();

/// Opens the store at [path] inside the browser's IndexedDB, or an
/// in-memory database when null. The file is encrypted by SQLite3 Multiple
/// Ciphers before it reaches IndexedDB, exactly like the file on a phone,
/// so the browser only ever holds ciphertext.
Future<ZtDatabaseHandle> ztOpenDatabase(String? path) async {
  final (sqlite, fs) = await _load();
  final db = path == null
      ? sqlite.openInMemory()
      // SQLite3 Multiple Ciphers wraps every registered file system;
      // opening through the wrapper is what makes the key apply.
      : sqlite.open(path, vfs: 'multipleciphers-$_vfsName');
  return ZtDatabaseHandle(db, () async {
    db.close();
    // Writes reach IndexedDB in the background; wait for them on close
    // (lock, sign out) so nothing is lost when the tab closes right after.
    await fs.flush();
  }, supportsWal: false);
}

Future<String> ztDatabasePath(String fileName) async => '/$fileName';

const _suffixes = ['', '-journal', '-wal', '-shm'];

Future<void> ztDeleteDatabase(String path) async {
  final (_, fs) = await _load();
  for (final suffix in _suffixes) {
    if (fs.xAccess('$path$suffix', 0) != 0) fs.xDelete('$path$suffix', 0);
  }
  await fs.flush();
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
