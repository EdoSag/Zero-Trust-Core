// A week with one meeting, a lunch habit and three tasks.
//
//   dart run example/zt_scheduler_example.dart
import 'package:zt_scheduler/zt_scheduler.dart';

void main() {
  final monday = DateTime.utc(2026, 11, 23);
  DateTime at(int day, int hour, [int minute = 0]) =>
      monday.add(Duration(days: day, hours: hour, minutes: minute));

  final result = plan(
    now: at(0, 8),
    hours: [
      PlanHours.sameEachDay(
        'work',
        days: {1, 2, 3, 4, 5},
        ranges: const [PlanRange.hm(9, 0, 17, 0)],
      ),
    ],
    busy: [PlanBusy(at(0, 10), at(0, 11))],
    habits: const [
      PlanHabit(
        id: 'lunch',
        minutes: 30,
        days: {1, 2, 3, 4, 5},
        ideal: 12 * 60 + 30,
        earliest: 11 * 60 + 30,
        latest: 14 * 60,
      ),
    ],
    tasks: [
      PlanTask(id: 'report', minutes: 240, due: at(1, 17)),
      const PlanTask(id: 'slides', minutes: 90, priority: PlanPriority.high),
      PlanTask(
        id: 'expenses',
        minutes: 30,
        priority: PlanPriority.low,
        due: at(0, 12),
      ),
    ],
    settings: const PlanSettings(horizonDays: 2),
  );

  String two(int v) => v.toString().padLeft(2, '0');
  String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
  const days = ['Mon', 'Tue'];
  for (final b in result.blocks) {
    final day = days[b.start.difference(monday).inDays];
    print('$day ${clock(b.start)}-${clock(b.end)}  ${b.itemId.padRight(9)}'
        '${b.reason!.name}');
  }
  print('at risk: ${result.risks}');
}
