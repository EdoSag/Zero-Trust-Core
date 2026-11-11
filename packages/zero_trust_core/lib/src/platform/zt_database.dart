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
