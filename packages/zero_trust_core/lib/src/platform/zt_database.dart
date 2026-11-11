import 'package:sqlite3/common.dart';

/// An open SQLite database plus how to close it on this platform.
class ZtDatabaseHandle {
  ZtDatabaseHandle(this.db, this._close, {required this.supportsWal});

  final CommonDatabase db;
  final Future<void> Function() _close;

  /// False on the web, where the browser storage can't share memory between
  /// connections, so the store keeps SQLite's default rollback journal.
  final bool supportsWal;

  Future<void> close() => _close();
}

/// The store is already open in another browser tab or window. Only one
/// tab at a time may use an account's store, so the two can't overwrite
/// each other's changes; close the other tab and try again.
class LocalStoreInUse implements Exception {
  const LocalStoreInUse(this.path);
  final String path;
  @override
  String toString() => 'LocalStoreInUse($path)';
}
