import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'zt_database.dart';

/// Web only (see the web version); kept here so apps can set it on any
/// platform without a conditional import.
String ztSqliteWasmUrl = 'sqlite3mc.wasm';

/// Opens the SQLite file at [path], or an in-memory database when null.
/// Uses the SQLite3 Multiple Ciphers build the app selects in its
/// `pubspec.yaml`.
Future<ZtDatabaseHandle> ztOpenDatabase(String? path) async {
  final db = path == null ? sqlite3.openInMemory() : sqlite3.open(path);
  return ZtDatabaseHandle(db, () async => db.close(), supportsWal: true);
}

/// Where a store named [fileName] lives: the app's support folder.
Future<String> ztDatabasePath(String fileName) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return '${dir.path}/$fileName';
}

const _suffixes = ['', '-wal', '-shm', '-journal'];

Future<void> ztDeleteDatabase(String path) async {
  for (final suffix in _suffixes) {
    final f = File('$path$suffix');
    if (await f.exists()) await f.delete();
  }
}

Future<void> ztMoveDatabaseAside(String path) async {
  final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  for (final suffix in _suffixes) {
    final f = File('$path$suffix');
    if (await f.exists()) await f.rename('$path.unreadable-$stamp$suffix');
  }
}

/// Browser-only: saves [bytes] through a download. Never called on a
/// device, where apps hand the file to the share sheet instead.
Future<void> ztDownloadFile(String fileName, Uint8List bytes) =>
    throw UnsupportedError('Downloads are for the web build only');
