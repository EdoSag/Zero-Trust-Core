import 'dart:async';
import 'dart:math';

import 'item_sync_engine.dart';

/// What the shared "Synced 2 min ago" row shows.
class SyncStatus {
  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.error,
    this.rejected = const [],
    this.conflicts = const [],
  });

  final bool isSyncing;

  /// End of the last successful sync on this device.
  final DateTime? lastSyncedAt;

  /// Why the last attempt failed; null once one succeeds.
  final Object? error;

  /// Items that couldn't be read (see [SyncResult.rejected]).
  final List<String> rejected;

  /// Local edits that lost to newer ones, kept until the app clears them.
  final List<SyncConflict> conflicts;

  SyncStatus _with({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    Object? error,
    bool clearError = false,
    List<String>? rejected,
    List<SyncConflict>? conflicts,
  }) =>
      SyncStatus(
        isSyncing: isSyncing ?? this.isSyncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        error: clearError ? null : error ?? this.error,
        rejected: rejected ?? this.rejected,
        conflicts: conflicts ?? this.conflicts,
      );
}

/// Decides when to sync, so every app syncs the same way:
/// - at [start] (the vault just unlocked) and on [resume];
/// - [debounce] after the last local edit ([localChange]);
/// - every [interval] while running, which also catches anything realtime
///   missed while the connection was down;
/// - after a failure, again after [minBackoff], doubling up to [maxBackoff],
///   so a device that comes back online catches up on its own.
///
/// Requests that arrive during a sync are folded into one more run after it.
class SyncScheduler {
  SyncScheduler({
    required Future<SyncResult> Function() sync,
    required void Function(SyncStatus) onStatus,
    this.interval = const Duration(minutes: 5),
    this.debounce = const Duration(seconds: 2),
    this.minBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _sync = sync,
        _onStatus = onStatus,
        _clock = clock ?? DateTime.now;

  final Duration interval;
  final Duration debounce;
  final Duration minBackoff;
  final Duration maxBackoff;

  final Future<SyncResult> Function() _sync;
  final void Function(SyncStatus) _onStatus;
  final DateTime Function() _clock;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  Timer? _timer;
  Future<void>? _inFlight;
  bool _again = false;
  bool _paused = false;
  bool _disposed = false;

  /// A local edit is waiting for its debounced push.
  bool _editPending = false;
  Duration? _backoff;

  /// The delay before the current retry, while backing off.
  Duration? get backoff => _backoff;

  /// Syncs now and keeps syncing on the schedule.
  Future<void> start() {
    _paused = false;
    return syncNow();
  }

  /// Syncs as soon as possible. Safe to call at any time.
  Future<void> syncNow() {
    if (_disposed) return Future.value();
    _timer?.cancel();
    _timer = null;
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _run();
  }

  /// Something was saved locally: push it shortly, batching quick edits.
  void localChange() {
    if (_disposed) return;
    _editPending = true;
    if (_paused) return;
    if (_inFlight != null) {
      _again = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(debounce, syncNow);
  }

  /// The app went to the background: stop the timers. An edit still waiting
  /// for its push goes now rather than at the next resume.
  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    if (_editPending) syncNow();
  }

  /// Back in the foreground: catch up now, then resume the schedule.
  Future<void> resume() => start();

  /// Takes realtime changes into the status.
  void applyLive(SyncResult result) {
    if (_disposed) return;
    final rejected = {..._status.rejected, ...result.rejected}.toList();
    _set(_status._with(
      rejected: rejected,
      conflicts: [..._status.conflicts, ...result.conflicts],
    ));
  }

  void clearConflicts() => _set(_status._with(conflicts: const []));

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    _editPending = false;
    _set(_status._with(isSyncing: true));
    Duration next;
    try {
      final result = await _sync();
      _backoff = null;
      next = interval;
      _set(_status._with(
        isSyncing: false,
        lastSyncedAt: _clock(),
        clearError: true,
        rejected: result.rejected,
        conflicts: [..._status.conflicts, ...result.conflicts],
      ));
    } catch (e) {
      final b = _backoff;
      _backoff = b == null
          ? minBackoff
          : Duration(
              microseconds:
                  min(b.inMicroseconds * 2, maxBackoff.inMicroseconds));
      next = _backoff!;
      _set(_status._with(isSyncing: false, error: e));
    } finally {
      _inFlight = null;
    }
    if (_disposed) return;
    if (_again) {
      _again = false;
      await syncNow();
      return;
    }
    if (!_paused) _timer = Timer(next, syncNow);
  }

  void _set(SyncStatus s) {
    if (_disposed) return;
    _status = s;
    _onStatus(s);
  }
}
