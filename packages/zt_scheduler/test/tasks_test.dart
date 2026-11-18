import 'package:test/test.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'support.dart';

void main() {
  group('where a task goes', () {
    test('the earliest free time in its hours', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.earliest);
      expect(r.create.map(show), ['a:0 d0 09:00-10:00']);
      expect(r.update, isEmpty);
      expect(r.delete, isEmpty);
      expect(r.risks, isEmpty);
    });

    test('never outside its hours: Saturday waits for Monday', () {
      final r = plan(
        now: at(5, 10),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d7 09:00-10:00']);
    });

    test('on the grid, and with half an hour of notice', () {
      final r = plan(
        now: at(0, 9, 7),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60)],
      );
      // 9:07 plus the 30 minutes in which blocks are left alone, rounded
      // up to the next quarter.
      expect(shown(r), ['a:0 d0 09:45-10:45']);
    });

    test('or as soon as the grid allows, when the notice is set to none', () {
      final r = plan(
        now: at(0, 9, 7),
        hours: [work],
        settings: const PlanSettings(bufferAfterEvents: 0, freezeMinutes: 0),
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d0 09:15-10:15']);
    });

    test('in the hours it names', () {
      final r = plan(
        now: at(0, 8),
        hours: [work, personal],
        settings: plain,
        tasks: [task('a', 60, hoursId: 'personal')],
      );
      expect(shown(r), ['a:0 d0 18:00-19:00']);
    });

    test('not before its start date', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60, notBefore: at(2, 13))],
      );
      expect(shown(r), ['a:0 d2 13:00-14:00']);
    });

    test('around events', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 9), at(0, 10))],
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d0 10:00-11:00']);
    });

    test('with a break after events, but not after unbuffered ones', () {
      const settings = PlanSettings(bufferAfterEvents: 10);
      final afterMeeting = plan(
        now: at(0, 8),
        hours: [work],
        settings: settings,
        busy: [PlanBusy(at(0, 9), at(0, 10))],
        tasks: [task('a', 60)],
      );
      expect(shown(afterMeeting), ['a:0 d0 10:15-11:15']);

      final afterOther = plan(
        now: at(0, 8),
        hours: [work],
        settings: settings,
        busy: [PlanBusy(at(0, 9), at(0, 10), buffered: false)],
        tasks: [task('a', 60)],
      );
      expect(shown(afterOther), ['a:0 d0 10:00-11:00']);
    });

    test('with a break before events', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: const PlanSettings(
          bufferBeforeEvents: 15,
          bufferAfterEvents: 0,
        ),
        busy: [PlanBusy(at(0, 10), at(0, 11))],
        tasks: [task('a', 60)],
      );
      // 9:00 to 9:45 is too short for the whole task, so it isn't split.
      expect(shown(r), ['a:0 d0 11:00-12:00']);
    });

    test('with a break after each block', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: const PlanSettings(
          bufferAfterEvents: 0,
          breakAfterBlocks: 15,
        ),
        tasks: [task('a', 60), task('b', 60, order: 1)],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00', 'b:0 d0 10:15-11:15']);
    });
  });

  group('blocks of one task', () {
    test('a long task is cut into blocks, two a day with a gap', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 300)],
      );
      expect(shown(r), [
        'a:0 d0 09:00-11:00',
        'a:1 d0 12:00-14:00',
        'a:2 d1 09:00-10:00',
      ]);
    });

    test('the last piece is never shorter than the shortest block', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 75, minChunk: 30, maxChunk: 60)],
      );
      expect(shown(r), ['a:0 d0 09:00-09:45', 'a:1 d0 10:45-11:15']);
    });

    test('whole blocks are preferred to starting a little sooner', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 9, 45), at(0, 11))],
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d0 11:00-12:00']);
    });

    test('but it is cut smaller when that is the only way to fit', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
        busy: [
          PlanBusy(at(0, 9, 45), at(0, 12)),
          PlanBusy(at(0, 12, 30), at(0, 17)),
        ],
        tasks: [task('a', 60)],
      );
      expect(shown(r), ['a:0 d0 09:00-09:30', 'a:1 d0 12:00-12:30']);
      expect(r.risks, isEmpty);
    });

    test('no more task time in a day than the limit', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: const PlanSettings(
          bufferAfterEvents: 0,
          maxTaskMinutesPerDay: 120,
        ),
        tasks: [task('a', 120), task('b', 120, order: 1)],
      );
      expect(shown(r), ['a:0 d0 09:00-11:00', 'b:0 d1 09:00-11:00']);
    });

    test('time already spent is not planned again', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60, logged: 30)],
      );
      expect(shown(r), ['a:0 d0 09:00-09:30']);
    });
  });

  group('which task goes first', () {
    test('the more important one', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('low', 60, priority: PlanPriority.low),
          task('crit', 60, priority: PlanPriority.critical, order: 1),
        ],
      );
      expect(shown(r), ['crit:0 d0 09:00-10:00', 'low:0 d0 10:00-11:00']);
    });

    test('then the one due sooner, then the one with no due date', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('never', 60),
          task('thu', 60, due: at(3, 17), order: 1),
          task('tue', 60, due: at(1, 17), order: 2),
        ],
      );
      expect(shown(r), [
        'tue:0 d0 09:00-10:00',
        'thu:0 d0 10:00-11:00',
        'never:0 d0 11:00-12:00',
      ]);
    });

    test('the order the tasks are given in makes no difference', () {
      final tasks = [
        task('a', 90, priority: PlanPriority.high, due: at(2, 17)),
        task('b', 240, order: 3),
        task('c', 45, priority: PlanPriority.low, due: at(0, 15), order: 1),
        task('d', 300, priority: PlanPriority.critical, order: 2),
      ];
      List<String> run(List<PlanTask> list) => shown(
            plan(
              now: at(0, 8),
              hours: [work],
              settings: plain,
              busy: [PlanBusy(at(0, 10), at(0, 11))],
              tasks: list,
            ),
          );
      final expected = run(tasks);
      expect(run(tasks.reversed.toList()), expected);
      expect(run([tasks[2], tasks[0], tasks[3], tasks[1]]), expected);
    });
  });

  group('due dates', () {
    test('every block ends by the due date', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        busy: [PlanBusy(at(0, 9), at(0, 10))],
        tasks: [task('a', 120, due: at(0, 12))],
      );
      expect(shown(r), ['a:0 d0 10:00-12:00']);
      expect(r.risks, isEmpty);
    });

    test('a tight one may use more blocks in a day than usual', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 360, due: at(0, 17))],
      );
      expect(shown(r), [
        'a:0 d0 09:00-11:00',
        'a:1 d0 11:00-12:00',
        'a:2 d0 12:00-14:00',
        'a:3 d0 14:00-15:00',
      ]);
      expect(reasonOf(r, 'a:0'), PlanReason.earliest);
      expect(reasonOf(r, 'a:1'), PlanReason.deadline);
      expect(reasonOf(r, 'a:2'), PlanReason.earliest);
      expect(reasonOf(r, 'a:3'), PlanReason.deadline);
      expect(r.risks, isEmpty);
    });

    test('what cannot fit is planned after it and reported', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 240, due: at(0, 12))],
      );
      expect(shown(r), [
        'a:0 d0 09:00-11:00',
        'a:1 d0 11:00-12:00',
        'a:2 d1 09:00-10:00',
      ]);
      expect(reasonOf(r, 'a:2'), PlanReason.late);
      expect(r.risks, hasLength(1));
      expect(r.risks.single.taskId, 'a');
      expect(r.risks.single.minutesLate, 60);
      expect(r.risks.single.minutesUnplanned, 0);
    });

    test('an overdue task is planned as soon as possible, and reported', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [task('a', 60, due: at(-1, 17))],
      );
      expect(shown(r), ['a:0 d0 09:00-10:00']);
      expect(reasonOf(r, 'a:0'), PlanReason.late);
      expect(r.risks.single.minutesLate, 60);
    });

    test('a task that would be late goes ahead of one with time to spare', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('big', 720),
          task('soon', 180, priority: PlanPriority.low, due: at(0, 13)),
        ],
      );
      expect(r.risks, isEmpty);
      expect(
          shown(r, 'soon'), ['soon:0 d0 09:00-11:00', 'soon:1 d0 12:00-13:00']);
      expect(shown(r, 'big'), [
        'big:0 d0 13:00-15:00',
        'big:1 d1 09:00-11:00',
        'big:2 d1 12:00-14:00',
        'big:3 d2 09:00-11:00',
        'big:4 d2 12:00-14:00',
        'big:5 d3 09:00-11:00',
      ]);
    });

    test('but never if that makes something more important late', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('high', 240, priority: PlanPriority.high, due: at(0, 13)),
          task('low', 120, priority: PlanPriority.low, due: at(0, 11)),
        ],
      );
      expect(shown(r, 'high'), [
        'high:0 d0 09:00-11:00',
        'high:1 d0 11:00-12:00',
        'high:2 d0 12:00-13:00',
      ]);
      expect(shown(r, 'low'), ['low:0 d0 13:00-15:00']);
      expect(r.risks.map((x) => x.taskId), ['low']);
      expect(r.risks.single.minutesLate, 120);
    });

    test('only the part that makes the due date goes ahead', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: plain,
        tasks: [
          task('big', 240, priority: PlanPriority.critical, due: at(2, 17)),
          task('soon', 240, priority: PlanPriority.low, due: at(0, 11)),
        ],
      );
      // Two hours of "soon" fit by 11:00 and go first. Its other two hours
      // are late either way, so they wait behind the critical task.
      expect(shown(r), [
        'soon:0 d0 09:00-11:00',
        'big:0 d0 11:00-13:00',
        'big:1 d0 14:00-16:00',
        'soon:1 d1 09:00-11:00',
      ]);
      expect(reasonOf(r, 'soon:1'), PlanReason.late);
      expect(r.risks.single.taskId, 'soon');
      expect(r.risks.single.minutesLate, 120);
    });

    test('what finds no room in the days planned is reported', () {
      final r = plan(
        now: at(0, 8),
        hours: [work],
        settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
        tasks: [task('a', 600)],
      );
      expect(shown(r), ['a:0 d0 09:00-11:00', 'a:1 d0 12:00-14:00']);
      expect(r.risks.single.due, isNull);
      expect(r.risks.single.minutesLate, 0);
      expect(r.risks.single.minutesUnplanned, 360);
    });
  });

  group('bad input', () {
    test('a time that is not wall-clock UTC is refused', () {
      expect(
        () => plan(now: DateTime(2026, 11, 23, 8), hours: [work]),
        throwsArgumentError,
      );
      expect(
        () => plan(
          now: at(0, 8),
          hours: [work],
          busy: [PlanBusy(DateTime(2026, 11, 23, 9), at(0, 10))],
        ),
        throwsArgumentError,
      );
      expect(
        () => plan(
          now: at(0, 8),
          hours: [work],
          tasks: [task('a', 60, due: DateTime(2026, 11, 24))],
        ),
        throwsArgumentError,
      );
    });

    test('two tasks or two blocks with one id are refused', () {
      expect(
        () => plan(
          now: at(0, 8),
          hours: [work],
          tasks: [task('a', 60), task('a', 30)],
        ),
        throwsArgumentError,
      );
      expect(
        () => plan(
          now: at(0, 8),
          hours: [work],
          tasks: [task('a', 60)],
          existing: [
            block('a:0', at(0, 9), at(0, 10)),
            block('a:0', at(0, 11), at(0, 12)),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('tasks with no hours at all are refused', () {
      expect(
        () => plan(now: at(0, 8), hours: [], tasks: [task('a', 60)]),
        throwsArgumentError,
      );
    });

    test('PlanTime keeps the date and time of day both ways', () {
      final local = DateTime(2026, 3, 29, 9, 30);
      final wall = PlanTime.wall(local);
      expect(wall, DateTime.utc(2026, 3, 29, 9, 30));
      expect(PlanTime.local(wall), local);
    });
  });
}
