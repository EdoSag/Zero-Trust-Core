import 'package:test/test.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'support.dart';

void main() {
  group('a calm calendar', () {
    test('a block stays where it is when something new is added', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60), task('c', 60, priority: PlanPriority.low)],
        existing: [block('a:0', at(1, 10), at(1, 11))],
      );
      expect(shown(r), ['c:0 d0 09:00-10:00', 'a:0 d1 10:00-11:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.kept);
      expect(r.create.map(show), ['c:0 d0 09:00-10:00']);
      expect(r.update, isEmpty);
      expect(r.delete, isEmpty);
    });

    test('a new meeting on a block moves that block and no other', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 13), at(0, 14))],
        tasks: [task('a', 60), task('b', 60, order: 1)],
        existing: [
          block('a:0', at(0, 13), at(0, 14)),
          block('b:0', at(0, 14), at(0, 15)),
        ],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00', 'b:0 d0 14:00-15:00']);
      // The moved block keeps its id, so the app updates one event.
      expect(r.update.map(show), ['a:0 d0 09:00-10:00']);
      expect(r.create, isEmpty);
      expect(r.delete, isEmpty);
    });

    test('a more important new task takes the place of a lesser one', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('low', 60, priority: PlanPriority.low),
          task('crit', 60, priority: PlanPriority.critical),
        ],
        existing: [block('low:0', at(0, 9), at(0, 10))],
      );
      expect(shown(r), ['crit:0 d0 09:00-10:00', 'low:0 d0 10:00-11:00']);
      expect(r.create.map(show), ['crit:0 d0 09:00-10:00']);
      expect(r.update.map(show), ['low:0 d0 10:00-11:00']);
    });

    test('a block stays put even when an earlier time is free', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
        existing: [block('a:0', at(2, 14), at(2, 15))],
      );
      expect(shown(r), ['a:0 d2 14:00-15:00']);
      expect(r.changesNothing, isTrue);
    });

    test('unless the week is rebuilt, and then it keeps its id', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
        existing: [block('a:0', at(2, 14), at(2, 15))],
        rebuild: true,
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(r.update.map(show), ['a:0 d0 09:00-10:00']);
      expect(r.create, isEmpty);
      expect(r.delete, isEmpty);
    });

    test('rebuilding leaves locked and done blocks alone', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 180)],
        existing: [
          block('a:0', at(1, 9), at(1, 10), done: true),
          block('a:1', at(2, 14), at(2, 15), locked: true),
          block('a:2', at(3, 9), at(3, 10)),
        ],
        rebuild: true,
      );
      expect(shown(r), [
        'a:2 d0 09:00-10:00',
        'a:0 d1 09:00-10:00',
        'a:1 d2 14:00-15:00',
      ]);
    });

    test('a block gives up its place when keeping it costs a due date', () {
      // "a" sits at 15:00 from an earlier plan. The new task can only be
      // done between 14:00 and 17:00 and there is a meeting until 15:00,
      // so leaving "a" there would make it late.
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 11), at(0, 15))],
        tasks: [
          task('a', 120, priority: PlanPriority.high),
          task(
            'b',
            120,
            priority: PlanPriority.low,
            notBefore: at(0, 14),
            due: at(0, 17),
          ),
        ],
        existing: [block('a:0', at(0, 15), at(0, 17))],
      );
      expect(shown(r), ['a:0 d0 09:00-11:00', 'b:0 d0 15:00-17:00']);
      expect(r.risks, isEmpty);
      expect(r.update.map(show), ['a:0 d0 09:00-11:00']);
    });

    test('planning again from a plan changes nothing', () {
      final scenarios = <({List<PlanTask> tasks, List<PlanBusy> busy})>[
        (tasks: [task('a', 300)], busy: []),
        (tasks: [task('a', 360, due: at(0, 17))], busy: []),
        (tasks: [task('a', 240, due: at(0, 12))], busy: []),
        (
          tasks: [
            task('big', 720),
            task('soon', 180, priority: PlanPriority.low, due: at(0, 13)),
          ],
          busy: [],
        ),
        (
          tasks: [
            task('high', 240, priority: PlanPriority.high, due: at(0, 13)),
            task('low', 120, priority: PlanPriority.low, due: at(0, 11)),
            task('x', 75, minChunk: 30, maxChunk: 60, order: 4),
          ],
          busy: [PlanBusy(at(1, 9, 30), at(1, 12))],
        ),
      ];
      for (final s in scenarios) {
        final first = plan(
          now: at(0, 8),
          hours: [work],
          settings: const PlanSettings(breakAfterBlocks: 5),
          busy: s.busy,
          tasks: s.tasks,
        );
        final second = plan(
          now: at(0, 8),
          hours: [work],
          settings: const PlanSettings(breakAfterBlocks: 5),
          busy: s.busy,
          tasks: s.tasks,
          existing: first.blocks,
        );
        expect(second.changesNothing, isTrue, reason: '${shown(first)}');
        expect(shown(second), shown(first));
      }
    });
  });

  group('blocks that never move', () {
    test('a locked block, even on top of an event', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 10, 30), at(0, 11, 30))],
        tasks: [task('a', 60)],
        existing: [block('a:0', at(0, 10), at(0, 11), locked: true)],
      );
      expect(shown(r), ['a:0 d0 10:00-11:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.locked);
      expect(r.conflicts, ['a:0']);
      expect(r.changesNothing, isTrue);
    });

    test('a locked block outside the hours counts toward the task', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 120)],
        existing: [block('a:0', at(0, 19), at(0, 20), locked: true)],
      );
      expect(shown(r), ['a:1 d0 09:00-10:00', 'a:0 d0 19:00-20:00']);
    });

    test('a block that is happening now', () {
      final r = plan(
        now: at(0, 9, 30),
        hours: [work],
        settings: plain,
        tasks: [task('a', 180)],
        existing: [block('a:0', at(0, 9), at(0, 11))],
      );
      expect(shown(r), ['a:0 d0 09:00-11:00', 'a:1 d0 12:00-13:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.inProgress);
    });

    test('a block that starts within half an hour', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 8), at(0, 12))],
        tasks: [task('a', 60)],
        existing: [block('a:0', at(0, 8, 15), at(0, 9, 15))],
      );
      expect(shown(r), ['a:0 d0 08:15-09:15']);
      expect(reasonOf(r, 'a:0'), PlanReason.startingSoon);
      expect(r.changesNothing, isTrue);
    });

    test('nothing else is planned on top of them', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60), task('b', 480, order: 1)],
        existing: [block('a:0', at(0, 9), at(0, 10), locked: true)],
      );
      expect(shown(r, 'b').first, 'b:0 d0 10:00-12:00');
    });
  });

  group('done and passed blocks', () {
    test('done blocks count toward the task and stay as history', () {
      final r = plan(
        now: at(0, 12),
        hours: [work],
        settings: plain,
        tasks: [task('a', 120)],
        existing: [block('a:0', at(0, 9), at(0, 10), done: true)],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00', 'a:1 d0 12:30-13:30']);
      expect(reasonOf(r, 'a:0'), PlanReason.done);
      expect(r.create.map(show), ['a:1 d0 12:30-13:30']);
      expect(r.update, isEmpty);
    });

    test('a task whose time is all done gets no more blocks', () {
      final r = plan(
        now: at(0, 12),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
        existing: [
          block('a:0', at(0, 9), at(0, 10), done: true),
          block('a:1', at(1, 9), at(1, 10)),
        ],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(r.delete, ['a:1']);
    });

    test('a passed block waits for an answer until the day ends', () {
      final r = plan(
        now: at(0, 15),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
        existing: [block('a:0', at(0, 9), at(0, 10))],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.awaitingAnswer);
      expect(r.changesNothing, isTrue);
    });

    test('unanswered the next day, its time is planned again', () {
      final r = plan(
        now: at(1, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
        existing: [block('a:0', at(0, 9), at(0, 10))],
      );
      expect(shown(r), ['a:1 d1 09:00-10:00']);
      expect(r.delete, ['a:0']);
      expect(r.create.map(show), ['a:1 d1 09:00-10:00']);
    });

    test('or counts as done, if the user chose that', () {
      final r = plan(
        now: at(1, 8),
        hours: [work],
        settings: const PlanSettings(
          bufferAfterEvents: 0,
          pastBlocks: PastBlocks.countAsDone,
        ),
        tasks: [task('a', 120)],
        existing: [block('a:0', at(0, 9), at(0, 10))],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00', 'a:1 d1 09:00-10:00']);
      expect(r.blocks.first.done, isTrue);
      expect(r.update.map(show), ['a:0 d0 09:00-10:00']);
    });
  });

  group('when the task changes', () {
    test('a task that is gone loses its blocks but keeps its history', () {
      final r = plan(
        now: at(0, 12),
        hours: [work],
        settings: plain,
        existing: [
          block('x:0', at(0, 9), at(0, 10), done: true),
          block('x:1', at(0, 14), at(0, 15)),
          block('x:2', at(1, 9), at(1, 10), locked: true),
        ],
      );
      expect(shown(r), ['x:0 d0 09:00-10:00']);
      expect(r.delete, ['x:1', 'x:2']);
    });

    test('a shorter estimate shortens or removes the last blocks', () {
      final existing = [
        block('a:0', at(0, 9), at(0, 11)),
        block('a:1', at(0, 12), at(0, 14)),
      ];
      final shorter = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 150)],
        existing: existing,
      );
      expect(shown(shorter), ['a:0 d0 09:00-11:00', 'a:1 d0 12:00-12:30']);
      expect(shorter.update.map(show), ['a:1 d0 12:00-12:30']);

      final half = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 120)],
        existing: existing,
      );
      expect(shown(half), ['a:0 d0 09:00-11:00']);
      expect(half.delete, ['a:1']);
    });

    test('a longer estimate adds a block and keeps the others', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 120)],
        existing: [block('a:0', at(0, 9), at(0, 10))],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00', 'a:1 d0 11:00-12:00']);
      expect(r.create.map(show), ['a:1 d0 11:00-12:00']);
      expect(r.update, isEmpty);
    });

    test('an earlier due date pulls a block forward', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60, due: at(0, 17))],
        existing: [block('a:0', at(2, 9), at(2, 10))],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(r.update.map(show), ['a:0 d0 09:00-10:00']);
    });
  });
}
