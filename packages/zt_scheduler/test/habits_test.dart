import 'package:test/test.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'support.dart';

/// Lunch on weekdays: 30 minutes, ideally 12:30, between 11:30 and 14:00.
PlanHabit lunch({int? minMinutes, String? hoursId, Set<int>? days}) =>
    PlanHabit(
      id: 'lunch',
      minutes: 30,
      minMinutes: minMinutes,
      days: days ?? {1, 2, 3, 4, 5},
      ideal: 12 * 60 + 30,
      earliest: 11 * 60 + 30,
      latest: 14 * 60,
      hoursId: hoursId,
    );

const threeDays = PlanSettings(bufferAfterEvents: 0, horizonDays: 3);

void main() {
  test('a habit takes its ideal time on each of its days', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: threeDays,
      habits: [lunch()],
    );
    expect(shown(r), [
      'lunch:20261123 d0 12:30-13:00',
      'lunch:20261124 d1 12:30-13:00',
      'lunch:20261125 d2 12:30-13:00',
    ]);
    expect(r.blocks.every((b) => b.reason == PlanReason.habitIdeal), isTrue);
    expect(r.blocks.every((b) => b.kind == PlanBlockKind.habit), isTrue);
    expect(r.skippedHabits, isEmpty);
  });

  test('only on its days', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: threeDays,
      habits: [
        lunch(days: {DateTime.tuesday})
      ],
    );
    expect(shown(r), ['lunch:20261124 d1 12:30-13:00']);
  });

  test('it moves to the nearest free time when its ideal time is busy', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      busy: [PlanBusy(at(0, 12), at(0, 13))],
      habits: [lunch()],
    );
    expect(shown(r), ['lunch:20261123 d0 13:00-13:30']);
    expect(r.blocks.single.reason, PlanReason.habitShifted);
  });

  test('it goes back to its ideal time when that frees up', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      habits: [lunch()],
      existing: [
        block(
          'lunch:20261123',
          at(0, 13),
          at(0, 13, 30),
          kind: PlanBlockKind.habit,
        ),
      ],
    );
    expect(shown(r), ['lunch:20261123 d0 12:30-13:00']);
    expect(r.update.map(show), ['lunch:20261123 d0 12:30-13:00']);
    expect(r.create, isEmpty);
    expect(r.delete, isEmpty);
  });

  test('with no room in its window it is skipped that day and reported', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 2),
      busy: [PlanBusy(at(0, 11, 30), at(0, 14))],
      habits: [lunch()],
    );
    expect(shown(r), ['lunch:20261124 d1 12:30-13:00']);
    expect(r.skippedHabits.single.habitId, 'lunch');
    expect(r.skippedHabits.single.day, monday);
  });

  test('or shortened, if it allows that', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      busy: [PlanBusy(at(0, 11, 30), at(0, 13, 45))],
      habits: [lunch(minMinutes: 15)],
    );
    expect(shown(r), ['lunch:20261123 d0 13:45-14:00']);
    expect(r.blocks.single.reason, PlanReason.habitShortened);
    expect(r.skippedHabits, isEmpty);
  });

  test('a day that is done, locked or already passed gets no new block', () {
    final done = plan(
      now: at(0, 12, 45),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      habits: [lunch()],
      existing: [
        block(
          'lunch:20261123',
          at(0, 12),
          at(0, 12, 30),
          kind: PlanBlockKind.habit,
          done: true,
        ),
      ],
    );
    expect(shown(done), ['lunch:20261123 d0 12:00-12:30']);
    expect(done.changesNothing, isTrue);

    final locked = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      habits: [lunch()],
      existing: [
        block(
          'lunch:20261123',
          at(0, 15),
          at(0, 15, 30),
          kind: PlanBlockKind.habit,
          locked: true,
        ),
      ],
    );
    expect(shown(locked), ['lunch:20261123 d0 15:00-15:30']);
    expect(locked.changesNothing, isTrue);

    final passed = plan(
      now: at(0, 15),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
      habits: [lunch()],
    );
    expect(passed.blocks, isEmpty);
    expect(passed.skippedHabits, isEmpty);
  });

  test('a locked block moved to another day does not clash with ids', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 2),
      habits: [lunch()],
      existing: [
        // Monday's lunch, dragged to Tuesday evening.
        block(
          'lunch:20261123',
          at(1, 18),
          at(1, 18, 30),
          kind: PlanBlockKind.habit,
          locked: true,
        ),
      ],
    );
    expect(shown(r), [
      'lunch:20261123.2 d0 12:30-13:00',
      'lunch:20261123 d1 18:00-18:30',
    ]);
  });

  test('kept inside its hours when it names them', () {
    final r = plan(
      now: at(4, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 2),
      habits: [
        lunch(hoursId: 'work', days: {DateTime.friday, DateTime.saturday}),
      ],
    );
    expect(shown(r), ['lunch:20261127 d4 12:30-13:00']);
    expect(r.skippedHabits.single.day, at(5, 0));
  });

  test('tasks are planned around habits, in whole blocks', () {
    final r = plan(
      now: at(0, 8),
      hours: [work],
      settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 2),
      tasks: [task('a', 300)],
      habits: [lunch()],
    );
    expect(shown(r, 'a'), [
      'a:0 d0 09:00-11:00',
      'a:1 d0 13:00-15:00',
      'a:2 d1 09:00-10:00',
    ]);
  });

  test('habits and tasks together plan the same again', () {
    List<PlanHabit> habits() => [
          lunch(minMinutes: 15),
          PlanHabit(
            id: 'gym',
            minutes: 60,
            days: {DateTime.monday, DateTime.wednesday},
            ideal: 18 * 60,
            earliest: 17 * 60,
            latest: 21 * 60,
            order: 1,
          ),
        ];
    final busy = [
      PlanBusy(at(0, 12), at(0, 13)),
      PlanBusy(at(2, 18), at(2, 19)),
    ];
    final tasks = [task('a', 300), task('b', 90, due: at(1, 12), order: 1)];
    final first = plan(
      now: at(0, 8),
      hours: [work, personal],
      settings: const PlanSettings(horizonDays: 5),
      busy: busy,
      tasks: tasks,
      habits: habits(),
    );
    expect(shown(first, 'gym'), [
      'gym:20261123 d0 18:00-19:00',
      'gym:20261125 d2 17:00-18:00',
    ]);
    final second = plan(
      now: at(0, 8),
      hours: [work, personal],
      settings: const PlanSettings(horizonDays: 5),
      busy: busy,
      tasks: tasks,
      habits: habits(),
      existing: first.blocks,
    );
    expect(second.changesNothing, isTrue);
  });

  group('a task and a habit with the same id', () {
    test('keep their own blocks and ids, plan after plan', () {
      const habit = PlanHabit(
        id: 'x',
        minutes: 30,
        days: {1},
        ideal: 12 * 60 + 30,
        earliest: 11 * 60 + 30,
        latest: 14 * 60,
      );
      PlanResult run([List<PlanBlock> existing = const []]) => plan(
            now: at(0, 8),
            hours: [work],
            settings: const PlanSettings(bufferAfterEvents: 0, horizonDays: 1),
            tasks: [task('x', 60)],
            habits: const [habit],
            existing: existing,
          );
      final first = run();
      expect(shown(first), ['x:0 d0 09:00-10:00', 'x:20261123 d0 12:30-13:00']);
      final again = run(first.blocks);
      expect(shown(again), shown(first));
      expect(again.changesNothing, isTrue);
    });
  });
}
