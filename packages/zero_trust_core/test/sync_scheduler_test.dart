import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// A sync function whose outcome each test controls.
class _Sync {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  SyncResult result = const SyncResult();

  Future<SyncResult> call() async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    if (fail) throw Exception('offline');
    return result;
  }
}

void main() {
  late _Sync sync;
  late List<SyncStatus> statuses;

  SyncScheduler scheduler() => SyncScheduler(
        sync: sync.call,
        onStatus: statuses.add,
        clock: () => DateTime.utc(2026, 10, 22, 12),
      );

  setUp(() {
    sync = _Sync();
    statuses = [];
  });

  test('syncs at start, then on the interval', () {
    fakeAsync((async) {
      final s = scheduler()..start();
      async.flushMicrotasks();
      expect(sync.calls, 1);
      expect(s.status.isSyncing, isFalse);
      expect(s.status.lastSyncedAt, DateTime.utc(2026, 10, 22, 12));
      expect(statuses.first.isSyncing, isTrue);

      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(sync.calls, 1);
      async.elapse(const Duration(seconds: 1));
      expect(sync.calls, 2);
      s.dispose();
    });
  });

  test('local edits are debounced into one sync', () {
    fakeAsync((async) {
      final s = scheduler()..start();
      async.flushMicrotasks();
      s.localChange();
      async.elapse(const Duration(seconds: 1));
      s.localChange();
      async.elapse(const Duration(seconds: 1));
      expect(sync.calls, 1);
      async.elapse(const Duration(seconds: 1));
      expect(sync.calls, 2);
      s.dispose();
    });
  });

  test('failures back off, doubling to a cap, and success resets it', () {
    fakeAsync((async) {
      sync.fail = true;
      final s = scheduler()..start();
      async.flushMicrotasks();
      expect(s.status.error, isA<Exception>());
      final waits = <Duration>[];
      for (var i = 0; i < 8; i++) {
        waits.add(s.backoff!);
        async.elapse(s.backoff!);
      }
      expect(waits.take(4), const [
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(seconds: 40),
      ]);
      expect(waits.last, const Duration(minutes: 5));
      expect(sync.calls, 9);

      // Back online: the next retry succeeds and the schedule is normal.
      sync.fail = false;
      async.elapse(s.backoff!);
      expect(s.status.error, isNull);
      expect(s.backoff, isNull);
      final calls = sync.calls;
      async.elapse(const Duration(minutes: 4));
      expect(sync.calls, calls);
      s.dispose();
    });
  });

  test('requests during a sync fold into one more run', () {
    fakeAsync((async) {
      sync.gate = Completer();
      final s = scheduler()..start();
      async.flushMicrotasks();
      s.syncNow();
      s.localChange();
      s.syncNow();
      expect(sync.calls, 1);
      sync.gate!.complete();
      sync.gate = null;
      async.flushMicrotasks();
      expect(sync.calls, 2);
      async.elapse(const Duration(seconds: 3));
      expect(sync.calls, 2);
      s.dispose();
    });
  });

  test('pause stops the schedule but sends a waiting edit; resume syncs', () {
    fakeAsync((async) {
      final s = scheduler()..start();
      async.flushMicrotasks();
      s.localChange();
      s.pause();
      async.flushMicrotasks();
      expect(sync.calls, 2); // the edit went right away

      async.elapse(const Duration(hours: 1));
      expect(sync.calls, 2);

      s.localChange(); // while paused: waits for resume
      async.elapse(const Duration(seconds: 10));
      expect(sync.calls, 2);
      s.resume();
      async.flushMicrotasks();
      expect(sync.calls, 3);
      s.dispose();
    });
  });

  test('conflicts accumulate until cleared; rejected follows the last sync',
      () {
    fakeAsync((async) {
      final lost = SyncConflict(
          itemId: 'n1',
          lostLocal: LocalItem(itemId: 'n1', updatedAt: DateTime.utc(2026)));
      sync.result = SyncResult(conflicts: [lost], rejected: const ['bad']);
      final s = scheduler()..start();
      async.flushMicrotasks();
      s.syncNow();
      async.flushMicrotasks();
      expect(s.status.conflicts, hasLength(2));
      expect(s.status.rejected, ['bad']);

      s.applyLive(const SyncResult(rejected: ['worse']));
      expect(s.status.rejected, ['bad', 'worse']);

      s.clearConflicts();
      expect(s.status.conflicts, isEmpty);

      sync.result = const SyncResult();
      s.syncNow();
      async.flushMicrotasks();
      expect(s.status.rejected, isEmpty);
      s.dispose();
    });
  });

  test('nothing runs after dispose', () {
    fakeAsync((async) {
      final s = scheduler()..start();
      async.flushMicrotasks();
      s.dispose();
      s.localChange();
      s.syncNow();
      async.elapse(const Duration(hours: 1));
      expect(sync.calls, 1);
    });
  });

  test('status labels', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    String label(SyncStatus s) => syncStatusLabel(s, now);
    expect(label(const SyncStatus()), 'Not synced yet');
    expect(label(const SyncStatus(isSyncing: true)), 'Syncing…');
    expect(
        label(SyncStatus(error: Exception())), "Couldn't sync. Tap to retry");
    expect(label(SyncStatus(lastSyncedAt: now)), 'Synced just now');
    expect(
        label(
            SyncStatus(lastSyncedAt: now.subtract(const Duration(minutes: 2)))),
        'Synced 2 min ago');
    expect(
        label(SyncStatus(lastSyncedAt: now.subtract(const Duration(hours: 3)))),
        'Synced 3 hours ago');
    expect(
        label(SyncStatus(lastSyncedAt: now.subtract(const Duration(days: 1)))),
        'Synced yesterday');
  });
}
