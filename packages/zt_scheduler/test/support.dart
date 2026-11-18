import 'package:zt_scheduler/zt_scheduler.dart';

/// Day 0 of every scenario: Monday 23 November 2026.
final monday = DateTime.utc(2026, 11, 23);

/// [hour]:[minute] on day [day] (0 is Monday, 5 is Saturday, 7 the next
/// Monday).
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 23 + day, hour, minute);

/// Monday to Friday, 9:00 to 17:00.
final work = PlanHours.sameEachDay(
  'work',
  days: {1, 2, 3, 4, 5},
  ranges: const [PlanRange.hm(9, 0, 17, 0)],
);

/// Every day, 18:00 to 21:00.
final personal = PlanHours.sameEachDay(
  'personal',
  days: {1, 2, 3, 4, 5, 6, 7},
  ranges: const [PlanRange.hm(18, 0, 21, 0)],
);

/// The defaults, without the break after events (scenarios that test the
/// break set it themselves).
const plain = PlanSettings(bufferAfterEvents: 0);

PlanTask task(
  String id,
  int minutes, {
  PlanPriority priority = PlanPriority.medium,
  DateTime? due,
  DateTime? notBefore,
  int? minChunk,
  int? maxChunk,
  String hoursId = 'work',
  int order = 0,
  int logged = 0,
}) =>
    PlanTask(
      id: id,
      minutes: minutes,
      minutesLogged: logged,
      priority: priority,
      due: due,
      notBefore: notBefore,
      minChunk: minChunk,
      maxChunk: maxChunk,
      hoursId: hoursId,
      order: order,
    );

PlanBlock block(
  String id,
  DateTime start,
  DateTime end, {
  String? of,
  PlanBlockKind kind = PlanBlockKind.task,
  bool locked = false,
  bool done = false,
}) =>
    PlanBlock(
      id: id,
      itemId: of ?? id.split(':').first,
      kind: kind,
      start: start,
      end: end,
      locked: locked,
      done: done,
    );

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "a:0 d0 09:00-10:00": the block's id, its day and its times.
String show(PlanBlock b) => '${b.id} d${b.start.difference(monday).inDays} '
    '${_clock(b.start)}-${_clock(b.end)}';

/// The plan's blocks, soonest first, as [show] writes them. With [of],
/// only that task's or habit's.
List<String> shown(PlanResult result, [String? of]) => [
      for (final b in result.blocks)
        if (of == null || b.itemId == of) show(b),
    ];

/// The reason of the block called [id].
PlanReason? reasonOf(PlanResult result, String id) =>
    result.blocks.firstWhere((b) => b.id == id).reason;
