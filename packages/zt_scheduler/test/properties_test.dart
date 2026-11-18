import 'dart:math';

import 'package:test/test.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'support.dart';

/// What must hold for every plan, checked on many made-up calendars.

const _unmoved = {
  PlanReason.done,
  PlanReason.locked,
  PlanReason.inProgress,
  PlanReason.startingSoon,
  PlanReason.awaitingAnswer,
};

class _Case {
  _Case(int seed) {
    final r = Random(seed);
    T pick<T>(List<T> of) => of[r.nextInt(of.length)];

    now = at(r.nextInt(4), 7 + r.nextInt(9), r.nextInt(12) * 5);
    settings = PlanSettings(
      slotMinutes: pick([15, 15, 30, 5]),
      horizonDays: pick([7, 14]),
      bufferBeforeEvents: pick([0, 0, 5]),
      bufferAfterEvents: pick([0, 10]),
      breakAfterBlocks: pick([0, 5, 15]),
      maxTaskMinutesPerDay: pick([240, 360, 480]),
      maxChunksPerDay: pick([1, 2, 3]),
      sameTaskGapMinutes: pick([0, 60]),
    );
    busy = [
      for (var i = r.nextInt(13); i > 0; i--)
        () {
          final start = at(r.nextInt(10), 7 + r.nextInt(13), r.nextInt(12) * 5);
          return PlanBusy(
            start,
            start.add(Duration(minutes: 15 + r.nextInt(12) * 15)),
            buffered: r.nextInt(4) != 0,
          );
        }(),
    ];
    tasks = [
      for (var i = r.nextInt(11); i > 0; i--)
        () {
          final minChunk = pick([null, 15, 30, 45]);
          return PlanTask(
            id: 't$i',
            minutes: 15 + r.nextInt(40) * 15,
            minutesLogged: pick([0, 0, 0, 30]),
            priority: pick(PlanPriority.values),
            due: r.nextBool()
                ? at(r.nextInt(9), 9 + r.nextInt(10), r.nextInt(4) * 15)
                : null,
            notBefore:
                r.nextInt(4) == 0 ? at(r.nextInt(6), 9 + r.nextInt(8)) : null,
            minChunk: minChunk,
            maxChunk: pick([null, 60, 90, 180]),
            hoursId: pick(['work', 'work', 'personal']),
            order: r.nextInt(3),
          );
        }(),
    ];
    habits = [
      for (var i = r.nextInt(3); i > 0; i--)
        PlanHabit(
          id: 'h$i',
          minutes: pick([30, 45, 60]),
          minMinutes: pick([null, 15]),
          days: {
            for (var d = 1; d <= 7; d++)
              if (r.nextInt(3) != 0) d,
          },
          ideal: (11 + i * 3) * 60 + 30,
          earliest: (10 + i * 3) * 60,
          latest: (14 + i * 3) * 60,
          hoursId: pick([null, null, 'work']),
          order: i,
        ),
    ];
  }

  late final DateTime now;
  late final PlanSettings settings;
  late final List<PlanBusy> busy;
  late final List<PlanTask> tasks;
  late final List<PlanHabit> habits;

  PlanResult run({DateTime? at, List<PlanBlock> existing = const []}) => plan(
        now: at ?? now,
        hours: [work, personal],
        settings: settings,
        busy: busy,
        tasks: tasks,
        habits: habits,
        existing: existing,
      );
}

int _ceil(int minutes, int slot) => ((minutes + slot - 1) ~/ slot) * slot;

bool _inHours(PlanHours hours, PlanBlock b) {
  final day = DateTime.utc(b.start.year, b.start.month, b.start.day);
  for (final r in hours.ranges[b.start.weekday] ?? const <PlanRange>[]) {
    final from = day.add(Duration(minutes: r.start));
    final to = day.add(Duration(minutes: r.end));
    if (!b.start.isBefore(from) && !b.end.isAfter(to)) return true;
  }
  return false;
}

void _check(_Case c, PlanResult r, DateTime now, {required bool fresh}) {
  final s = c.settings;
  final tasks = {for (final t in c.tasks) t.id: t};
  final habits = {for (final h in c.habits) h.id: h};
  final placed = [
    for (final b in r.blocks)
      if (!_unmoved.contains(b.reason)) b,
  ];
  final pause = Duration(minutes: s.breakAfterBlocks);

  expect({for (final b in r.blocks) b.id}.length, r.blocks.length,
      reason: 'ids are unique');

  for (final b in placed) {
    expect(b.start.isBefore(now), isFalse, reason: '$b starts in the past');
    expect(b.start.minute % s.slotMinutes, 0, reason: '$b is off the grid');
    expect(b.minutes % s.slotMinutes, 0, reason: '$b has an odd length');
    expect(b.minutes, greaterThan(0));

    // Never on an event or in the breaks around it.
    final tail = b.kind == PlanBlockKind.task ? pause : Duration.zero;
    for (final e in c.busy) {
      final from = e.start.subtract(
        Duration(minutes: e.buffered ? s.bufferBeforeEvents : 0),
      );
      final to = e.end.add(
        Duration(minutes: e.buffered ? s.bufferAfterEvents : 0),
      );
      expect(
        b.start.isBefore(to) && b.end.add(tail).isAfter(from),
        isFalse,
        reason: '$b is on the event ${e.start} to ${e.end}',
      );
    }

    if (b.kind == PlanBlockKind.task) {
      final t = tasks[b.itemId]!;
      expect(_inHours(t.hoursId == 'work' ? work : personal, b), isTrue,
          reason: '$b is outside its hours');
      final longest = max(
        s.slotMinutes,
        ((t.maxChunk ?? s.defaultMaxChunk) ~/ s.slotMinutes) * s.slotMinutes,
      );
      expect(b.minutes, lessThanOrEqualTo(longest), reason: '$b is too long');
      if (t.notBefore != null) {
        expect(b.start.isBefore(t.notBefore!), isFalse,
            reason: '$b is before its start date');
      }
      if (t.due != null && b.reason != PlanReason.late) {
        expect(b.end.isAfter(t.due!), isFalse, reason: '$b is after its due');
      }
    } else {
      final h = habits[b.itemId]!;
      final minuteOfDay = b.start.hour * 60 + b.start.minute;
      expect(minuteOfDay, greaterThanOrEqualTo(h.earliest));
      expect(minuteOfDay + b.minutes, lessThanOrEqualTo(h.latest));
      expect(h.days, contains(b.start.weekday));
      if (h.hoursId != null) expect(_inHours(work, b), isTrue);
    }
  }

  // Nothing the planner placed overlaps anything else on the plan, and a
  // task block is followed by its break.
  for (final a in placed) {
    for (final b in r.blocks) {
      if (identical(a, b) || b.reason == PlanReason.done) continue;
      final aTail = a.kind == PlanBlockKind.task ? pause : Duration.zero;
      final bTail = b.kind == PlanBlockKind.task ? pause : Duration.zero;
      final clash = a.start.isBefore(b.end.add(bTail)) &&
          b.start.isBefore(a.end.add(aTail));
      // A passed block's break is over too.
      if (b.reason == PlanReason.awaitingAnswer) continue;
      expect(clash, isFalse, reason: '$a and $b overlap');
    }
  }

  // No day holds more task time than the limit.
  final perDay = <DateTime, int>{};
  for (final b in r.blocks) {
    if (b.kind != PlanBlockKind.task) continue;
    final day = DateTime.utc(b.start.year, b.start.month, b.start.day);
    perDay[day] = (perDay[day] ?? 0) + b.minutes;
  }
  if (fresh) {
    for (final e in perDay.entries) {
      expect(e.value, lessThanOrEqualTo(s.maxTaskMinutesPerDay),
          reason: '${e.key} is over the daily limit');
    }
  }

  // Every minute of every task is either planned or reported.
  final risks = {for (final x in r.risks) x.taskId: x};
  for (final t in c.tasks) {
    final mine = r.blocks.where((b) => b.itemId == t.id).toList();
    final planned = mine.fold(0, (sum, b) => sum + b.minutes);
    final late = mine
        .where((b) => b.reason == PlanReason.late)
        .fold(0, (sum, b) => sum + b.minutes);
    final risk = risks[t.id];
    if (fresh) {
      final want = max(0, _ceil(t.minutes, s.slotMinutes) - t.minutesLogged);
      expect(
          planned + (risk?.minutesUnplanned ?? 0), _ceil(want, s.slotMinutes),
          reason: '${t.id} is not fully planned or reported');
    }
    expect(risk?.minutesLate ?? 0, late, reason: '${t.id} late minutes');
  }
}

void main() {
  test('every plan keeps the rules, and planning again changes nothing', () {
    for (var seed = 0; seed < 400; seed++) {
      final c = _Case(seed);
      final first = c.run();
      try {
        _check(c, first, c.now, fresh: true);
        expect(first.delete, isEmpty);
        expect(first.update, isEmpty);
        expect(first.create.length, first.blocks.length);

        final again = c.run(existing: first.blocks);
        expect(again.changesNothing, isTrue, reason: 'second run changed it');
        expect(shown(again), shown(first));
      } on TestFailure catch (e) {
        fail('seed $seed: ${e.message}');
      }
    }
  });

  test('an hour or two later, a plan where everything fits is unchanged', () {
    var checked = 0;
    for (var seed = 0; seed < 600; seed++) {
      final c = _Case(seed);
      final first = c.run();
      final later = c.now.add(Duration(minutes: 60 + (seed % 5) * 15));
      if (later.day != c.now.day) continue;
      try {
        final second = c.run(at: later, existing: first.blocks);
        _check(c, second, later, fresh: false);
        if (first.risks.isEmpty) {
          // Nothing is short of time, so nothing has a reason to move.
          checked++;
          expect(second.changesNothing, isTrue,
              reason: 'create ${second.create} update ${second.update} '
                  'delete ${second.delete}');
        }
        final third = c.run(at: later, existing: second.blocks);
        expect(third.changesNothing, isTrue, reason: 'third run changed it');
      } on TestFailure catch (e) {
        fail('seed $seed: ${e.message}');
      }
    }
    expect(checked, greaterThan(100));
  });

  test('days later, with unanswered blocks, the rules still hold', () {
    for (var seed = 0; seed < 200; seed++) {
      final c = _Case(seed);
      final first = c.run();
      final later = c.now.add(Duration(days: 1 + seed % 3, minutes: 45));
      try {
        final second = c.run(at: later, existing: first.blocks);
        _check(c, second, later, fresh: false);
        final third = c.run(at: later, existing: second.blocks);
        expect(third.changesNothing, isTrue, reason: 'third run changed it');
      } on TestFailure catch (e) {
        fail('seed $seed: ${e.message}');
      }
    }
  });

  test('the order of the inputs makes no difference', () {
    for (var seed = 0; seed < 100; seed++) {
      final c = _Case(seed);
      final expected = shown(c.run());
      final shuffled = plan(
        now: c.now,
        hours: [personal, work].reversed.toList(),
        settings: c.settings,
        busy: c.busy.reversed.toList(),
        tasks: [...c.tasks]..shuffle(Random(seed)),
        habits: c.habits.reversed.toList(),
      );
      expect(shown(shuffled), expected, reason: 'seed $seed');
    }
  });

  test('a busy month plans in well under a second', () {
    final tasks = [
      for (var i = 0; i < 60; i++)
        PlanTask(
          id: 't$i',
          minutes: 60 + (i % 6) * 45,
          priority: PlanPriority.values[i % 4],
          due: i.isEven ? at(2 + i % 20, 17) : null,
          order: i,
        ),
    ];
    final busy = [
      for (var d = 0; d < 28; d++)
        for (final h in [10, 13, 15]) PlanBusy(at(d, h), at(d, h, 45)),
    ];
    final watch = Stopwatch()..start();
    final r = plan(now: at(0, 8), hours: [work], busy: busy, tasks: tasks);
    watch.stop();
    expect(r.blocks, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
