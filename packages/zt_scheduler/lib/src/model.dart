/// The planner's inputs and outputs.
///
/// **Times are wall-clock times carried as UTC [DateTime]s.** "Monday 09:00"
/// is `DateTime.utc(2026, 11, 23, 9)` whatever zone the phone is in, so
/// working hours mean the same thing every day, including the days the
/// clocks change. The app converts its local times with [PlanTime.wall] on
/// the way in and [PlanTime.local] on the way out. A [DateTime] that is not
/// UTC is refused, so a missed conversion fails loudly instead of planning
/// at the wrong hour.
library;

/// Conversions between the phone's local time and the planner's wall-clock
/// time.
abstract final class PlanTime {
  /// [local] as the planner sees it: the same date and time of day.
  static DateTime wall(DateTime local) => DateTime.utc(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
      );

  /// A planner time back as a local time: the same date and time of day.
  static DateTime local(DateTime wall) =>
      DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
}

/// How much a task matters. The same four levels ZT Tasks has.
enum PlanPriority { critical, high, medium, low }

/// What a block is for.
enum PlanBlockKind { task, habit }

/// What happens to a block whose time has passed without the user saying
/// whether it was done.
enum PastBlocks {
  /// It waits for an answer until the end of that day, then its time goes
  /// back to the task and is planned again.
  askThenReplan,

  /// It counts as done.
  countAsDone,
}

/// Why a block is where it is. The app turns this into a sentence.
enum PlanReason {
  /// Marked done.
  done,

  /// The user locked it here.
  locked,

  /// It is happening now.
  inProgress,

  /// It starts too soon to move.
  startingSoon,

  /// Its time has passed today and the user hasn't said if it was done.
  awaitingAnswer,

  /// It was already here and still fits.
  kept,

  /// The earliest free time in the task's hours.
  earliest,

  /// Needed to finish before the due date, so the usual limits on blocks
  /// per day were set aside.
  deadline,

  /// No room before the due date; this is the earliest time after it.
  late,

  /// A habit at its ideal time.
  habitIdeal,

  /// A habit as near its ideal time as there was room.
  habitShifted,

  /// A habit shortened to fit.
  habitShortened,
}

/// A range of minutes of the day, `[start, end)`: 9:00 to 17:00 is
/// `PlanRange(540, 1020)`.
class PlanRange {
  const PlanRange(this.start, this.end)
      : assert(start >= 0 && end <= 1440 && start < end);

  /// From hours and minutes: `PlanRange.hm(9, 0, 17, 0)`.
  const PlanRange.hm(int fromHour, int fromMinute, int toHour, int toMinute)
      : this(fromHour * 60 + fromMinute, toHour * 60 + toMinute);

  final int start;
  final int end;
}

/// When a kind of work may be planned: "work", "personal".
class PlanHours {
  const PlanHours(this.id, this.ranges);

  /// The same [ranges] on each of [days] ([DateTime.monday] ..
  /// [DateTime.sunday]).
  PlanHours.sameEachDay(
    this.id, {
    required Set<int> days,
    required List<PlanRange> ranges,
  }) : ranges = {for (final d in days) d: ranges};

  final String id;

  /// Weekday ([DateTime.monday] .. [DateTime.sunday]) to that day's ranges.
  /// A weekday that is missing has no hours.
  final Map<int, List<PlanRange>> ranges;
}

/// A time the user is busy: an event.
class PlanBusy {
  const PlanBusy(this.start, this.end, {this.buffered = true});

  final DateTime start;
  final DateTime end;

  /// Whether the breaks before and after events apply to this one. False
  /// for things that are busy but aren't meetings.
  final bool buffered;
}

/// A task to plan.
class PlanTask {
  const PlanTask({
    required this.id,
    required this.minutes,
    this.minutesLogged = 0,
    this.priority = PlanPriority.medium,
    this.due,
    this.notBefore,
    this.minChunk,
    this.maxChunk,
    this.hoursId = 'work',
    this.order = 0,
  });

  final String id;

  /// How long the whole task takes.
  final int minutes;

  /// Time already spent that no block on the calendar accounts for.
  final int minutesLogged;

  final PlanPriority priority;

  /// Every block should end by this time. Null: no due date.
  final DateTime? due;

  /// No block starts before this time.
  final DateTime? notBefore;

  /// Shortest and longest block. Null: the settings' defaults.
  final int? minChunk;
  final int? maxChunk;

  /// Which [PlanHours] it is planned in.
  final String hoursId;

  /// Breaks ties between tasks of the same priority and due date (smaller
  /// first), for example the time the task was created.
  final int order;
}

/// A routine with a preferred time: "Lunch, every day, 30 minutes, around
/// 12:30, between 11:30 and 14:00".
class PlanHabit {
  const PlanHabit({
    required this.id,
    required this.minutes,
    required this.days,
    required this.ideal,
    required this.earliest,
    required this.latest,
    this.minMinutes,
    this.hoursId,
    this.order = 0,
  });

  final String id;
  final int minutes;

  /// Shortest it may be cut to when the full length doesn't fit. Null: it
  /// is skipped that day instead.
  final int? minMinutes;

  /// The weekdays it happens on ([DateTime.monday] .. [DateTime.sunday]).
  final Set<int> days;

  /// Minute of the day it would ideally start.
  final int ideal;

  /// Minutes of the day it must start after and end by.
  final int earliest;
  final int latest;

  /// Also keep it inside these hours. Null: only [earliest] and [latest].
  final String? hoursId;

  /// Habits with a smaller [order] choose their time first.
  final int order;
}

/// A planned block: part of a task, or one day's habit.
class PlanBlock {
  const PlanBlock({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.start,
    required this.end,
    this.locked = false,
    this.done = false,
    this.reason,
  });

  /// Stable name of the block. The planner makes these up
  /// (`<task id>:<n>`, `<habit id>:<yyyymmdd>`) and keeps a block's id when
  /// it moves it, so the app can turn a move into an update.
  final String id;

  /// The task or habit it belongs to.
  final String itemId;
  final PlanBlockKind kind;
  final DateTime start;
  final DateTime end;

  /// The user put it here: the planner never moves or removes it.
  final bool locked;
  final bool done;

  /// Set on the blocks a plan returns.
  final PlanReason? reason;

  int get minutes => end.difference(start).inMinutes;

  PlanBlock copyWith({
    DateTime? start,
    DateTime? end,
    bool? done,
    PlanReason? reason,
  }) =>
      PlanBlock(
        id: id,
        itemId: itemId,
        kind: kind,
        start: start ?? this.start,
        end: end ?? this.end,
        locked: locked,
        done: done ?? this.done,
        reason: reason ?? this.reason,
      );

  /// Same block at the same time in the same state ([reason] aside).
  bool sameAs(PlanBlock other) =>
      id == other.id &&
      itemId == other.itemId &&
      kind == other.kind &&
      start == other.start &&
      end == other.end &&
      locked == other.locked &&
      done == other.done;

  @override
  String toString() => 'PlanBlock($id ${start.toIso8601String()} to '
      '${end.toIso8601String()}'
      '${locked ? ' locked' : ''}${done ? ' done' : ''}'
      '${reason == null ? '' : ' ${reason!.name}'})';
}

/// The planner's knobs.
class PlanSettings {
  const PlanSettings({
    this.slotMinutes = 15,
    this.horizonDays = 28,
    this.freezeMinutes = 30,
    this.bufferBeforeEvents = 0,
    this.bufferAfterEvents = 10,
    this.breakAfterBlocks = 0,
    this.maxTaskMinutesPerDay = 360,
    this.maxChunksPerDay = 2,
    this.sameTaskGapMinutes = 60,
    this.defaultMinChunk = 30,
    this.defaultMaxChunk = 120,
    this.pastBlocks = PastBlocks.askThenReplan,
  })  : assert(slotMinutes > 0),
        assert(horizonDays > 0),
        assert(defaultMinChunk > 0 && defaultMinChunk <= defaultMaxChunk);

  /// Blocks start on this grid (15: 9:00, 9:15, ...) and last a multiple
  /// of it.
  final int slotMinutes;

  /// How many days ahead, counting today, are planned.
  final int horizonDays;

  /// A block that starts within this many minutes is left alone, and no
  /// new block starts sooner than this: the notice the user gets.
  final int freezeMinutes;

  /// Free minutes kept before and after each buffered [PlanBusy].
  final int bufferBeforeEvents;
  final int bufferAfterEvents;

  /// Free minutes kept after each task block.
  final int breakAfterBlocks;

  /// Most minutes of task blocks in one day.
  final int maxTaskMinutesPerDay;

  /// Most blocks of one task in one day, and the gap kept between them.
  /// Both are set aside when a due date can't be met otherwise.
  final int maxChunksPerDay;
  final int sameTaskGapMinutes;

  /// Block sizes for tasks that don't set their own.
  final int defaultMinChunk;
  final int defaultMaxChunk;

  final PastBlocks pastBlocks;
}

/// A task that doesn't fit as it should.
class PlanRisk {
  const PlanRisk({
    required this.taskId,
    required this.due,
    required this.minutesLate,
    required this.minutesUnplanned,
  });

  final String taskId;
  final DateTime? due;

  /// Minutes planned after [due].
  final int minutesLate;

  /// Minutes that found no room in the days planned.
  final int minutesUnplanned;

  @override
  String toString() =>
      'PlanRisk($taskId late $minutesLate unplanned $minutesUnplanned)';
}

/// A habit that found no room on a day.
class SkippedHabit {
  const SkippedHabit(this.habitId, this.day);

  final String habitId;

  /// Midnight of the day.
  final DateTime day;

  @override
  String toString() => 'SkippedHabit($habitId ${day.toIso8601String()})';
}

/// What the plan is, and what to change to get there.
class PlanResult {
  const PlanResult({
    required this.blocks,
    required this.create,
    required this.update,
    required this.delete,
    required this.risks,
    required this.skippedHabits,
    required this.conflicts,
  });

  /// Every block of the plan, soonest first: the ones kept as they were
  /// and the new and moved ones.
  final List<PlanBlock> blocks;

  /// Blocks to add.
  final List<PlanBlock> create;

  /// Blocks that exist and now have another time or state.
  final List<PlanBlock> update;

  /// Ids of existing blocks to remove.
  final List<String> delete;

  /// Tasks that end after their due date or don't fit, most important
  /// first.
  final List<PlanRisk> risks;

  final List<SkippedHabit> skippedHabits;

  /// Ids of locked blocks that overlap a busy time. They are kept: the
  /// user chose the time.
  final List<String> conflicts;

  bool get changesNothing => create.isEmpty && update.isEmpty && delete.isEmpty;
}
