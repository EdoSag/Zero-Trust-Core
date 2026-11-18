import 'dart:math' as math;

import 'intervals.dart';
import 'model.dart';

const _dayMinutes = 1440;

/// How many times the planner tries moving a task that would be late ahead
/// of tasks that have time to spare.
const _maxRepairs = 8;

/// Plans [tasks] and [habits] into the free time [busy] and [hours] leave,
/// starting from the blocks that exist.
///
/// The rules, in order:
///
/// 1. Blocks that are done, locked, happening now, starting within
///    [PlanSettings.freezeMinutes] or waiting for an answer today stay
///    exactly as they are. Nothing new starts sooner than that either.
/// 2. Habits take the free time nearest their ideal time on their days.
/// 3. Tasks follow, most important first, then nearest due date. A task
///    keeps the blocks it has if they still fit; what is left goes into the
///    earliest free time in its hours, in blocks of its sizes. Whole blocks
///    come first: a task is cut into shorter pieces only when whole ones
///    don't fit. A more important task doesn't wait behind the blocks of a
///    lesser one: it takes the time, and the lesser block moves.
/// 4. A task that can't finish by its due date may use more blocks in a
///    day than usual. If that isn't enough, the part that can still make
///    the due date may go ahead of tasks that are due later or never, as
///    long as nothing more important ends up worse off. What still doesn't
///    fit is planned after the due date and reported in
///    [PlanResult.risks].
/// 5. Blocks are only left where they are while that costs no due date. If
///    it does, the tasks are placed afresh.
///
/// With [rebuild], rule 3 forgets where the task blocks are: every block
/// that isn't fixed by rule 1 is placed afresh, as early as it fits. This
/// is "tidy up my week"; the blocks still keep their ids.
///
/// Every time is a wall-clock UTC [DateTime] (see [PlanTime]); anything
/// else throws [ArgumentError].
///
/// The same inputs always give the same plan, whatever order the lists are
/// in, and planning again from a plan's own blocks changes nothing. As time
/// passes, a plan in which everything fits stays as it is; one that is
/// short of time may be rearranged when the order in rule 4 changes.
PlanResult plan({
  required DateTime now,
  required List<PlanHours> hours,
  PlanSettings settings = const PlanSettings(),
  List<PlanBusy> busy = const [],
  List<PlanTask> tasks = const [],
  List<PlanHabit> habits = const [],
  List<PlanBlock> existing = const [],
  bool rebuild = false,
}) =>
    _Planner(
      now: now,
      hours: hours,
      settings: settings,
      busy: busy,
      tasks: tasks,
      habits: habits,
      existing: existing,
      rebuild: rebuild,
    ).run();

int _minutes(DateTime time, String what) {
  if (!time.isUtc) {
    throw ArgumentError.value(
      time,
      what,
      'must be a wall-clock UTC time (see PlanTime.wall)',
    );
  }
  return time.millisecondsSinceEpoch ~/ 60000;
}

DateTime _time(int minutes) =>
    DateTime.fromMillisecondsSinceEpoch(minutes * 60000, isUtc: true);

int _dayOf(int minutes) => minutes ~/ _dayMinutes;

int _weekdayOf(int day) => _time(day * _dayMinutes).weekday;

/// An existing block, in minutes.
class _Old {
  _Old(this.block, this.start, this.end);
  final PlanBlock block;
  final int start;
  final int end;
  int get minutes => end - start;
}

/// A block the planner is placing.
class _Draft {
  _Draft(this.start, this.end, this.reason, {this.id});
  final int start;
  final int end;
  final PlanReason reason;
  String? id;
}

/// Which part of a task a step places.
enum _Stage {
  /// All of it: what fits by the due date, then the rest after it.
  all,

  /// Only what fits by the due date.
  onTime,

  /// Only what is left after the due date.
  late,
}

/// One step of an attempt: place [stage] of [task].
class _Step {
  const _Step(this.task, this.stage);
  final PlanTask task;
  final _Stage stage;
}

/// A task while an attempt is placing it.
class _Work {
  _Work({
    required this.task,
    required this.maxChunk,
    required this.minChunk,
    required this.dueAt,
    required this.notBefore,
    required this.need,
    required this.days,
  });

  final PlanTask task;
  final int maxChunk;
  final int minChunk;
  final int? dueAt;
  final int notBefore;

  /// Minutes still to place.
  int need;

  /// Minutes placed after the due date.
  int late = 0;

  /// The task's blocks so far, by day.
  final Map<int, List<(int, int)>> days;
  final drafts = <_Draft>[];

  /// Existing blocks of the task that were not left where they are. New
  /// blocks take their ids.
  final spare = <_Old>[];
}

/// One try at placing every task, in the order of its steps.
class _Outcome {
  _Outcome(this.steps, this.blocks, this.risks, this.shortfall);
  final List<_Step> steps;
  final List<PlanBlock> blocks;
  final List<PlanRisk> risks;

  /// Minutes late or unplanned of tasks with a due date, by priority, then
  /// unplanned minutes of tasks without one. Smaller is better, compared
  /// from the left.
  final List<int> shortfall;

  bool betterThan(_Outcome other) {
    for (var i = 0; i < shortfall.length; i++) {
      if (shortfall[i] != other.shortfall[i]) {
        return shortfall[i] < other.shortfall[i];
      }
    }
    return false;
  }
}

class _Planner {
  _Planner({
    required DateTime now,
    required this.hours,
    required this.settings,
    required List<PlanBusy> busy,
    required this.tasks,
    required this.habits,
    required List<PlanBlock> existing,
    required this.rebuild,
  }) : _now = _minutes(now, 'now') {
    _slot = settings.slotMinutes;
    // New blocks start no sooner than the blocks that are left alone for
    // starting soon, so a block the planner has just placed is never one
    // it can't move the next time.
    _planStart = _ceil(_now + math.max(1, settings.freezeMinutes));
    _today = _dayOf(_now);
    _horizonEnd = (_today + settings.horizonDays) * _dayMinutes;

    for (final h in hours) {
      if (_hoursById.containsKey(h.id)) {
        throw ArgumentError('Two hours are called ${h.id}');
      }
      _hoursById[h.id] = h;
    }
    for (final t in tasks) {
      if (_tasksById.containsKey(t.id)) {
        throw ArgumentError('Two tasks have the id ${t.id}');
      }
      _tasksById[t.id] = t;
    }
    for (final h in habits) {
      if (_habitsById.containsKey(h.id)) {
        throw ArgumentError('Two habits have the id ${h.id}');
      }
      _habitsById[h.id] = h;
    }
    if (tasks.isNotEmpty && hours.isEmpty) {
      throw ArgumentError('Tasks need at least one PlanHours');
    }

    final rawBusy = Intervals();
    for (final b in busy) {
      final s = _minutes(b.start, 'busy.start');
      final e = _minutes(b.end, 'busy.end');
      if (e <= s) continue;
      rawBusy.add(s, e);
      _occupied.add(
        s - (b.buffered ? settings.bufferBeforeEvents : 0),
        e + (b.buffered ? settings.bufferAfterEvents : 0),
      );
    }
    _sortExisting(existing, rawBusy);
    _placeHabits();
  }

  final List<PlanHours> hours;
  final PlanSettings settings;
  final List<PlanTask> tasks;
  final List<PlanHabit> habits;
  final bool rebuild;

  final int _now;
  late final int _slot;

  /// The first minute a new block may start.
  late final int _planStart;
  late final int _today;
  late final int _horizonEnd;

  final _hoursById = <String, PlanHours>{};
  final _tasksById = <String, PlanTask>{};
  final _habitsById = <String, PlanHabit>{};

  /// Every existing block, by id.
  final _existing = <String, PlanBlock>{};

  /// Ids in use: existing blocks and the ones made up in this run.
  final _ids = <String>{};

  /// Blocks that stay as they are (done or fixed), and the habit blocks,
  /// which don't depend on the order tasks are placed in.
  final _settled = <PlanBlock>[];

  /// Existing blocks the planner may move, by task or habit.
  final _movable = <String, List<_Old>>{};

  /// Busy times with their buffers, fixed blocks and habit blocks.
  final _occupied = Intervals();

  /// Minutes of task blocks already counted on each day.
  final _dayLoad = <int, int>{};

  /// Done and fixed blocks of each task, by day.
  final _taskDays = <String, Map<int, List<(int, int)>>>{};

  /// Minutes of each task that done blocks and fixed blocks account for.
  final _doneMinutes = <String, int>{};
  final _fixedMinutes = <String, int>{};

  /// `<habit id>|<day>` of days a done or fixed block already covers.
  final _habitDaysTaken = <String>{};

  final _skipped = <SkippedHabit>[];
  final _conflicts = <String>[];

  final _windows = <(String, int), List<(int, int)>>{};

  int _ceil(int minutes) => ((minutes + _slot - 1) ~/ _slot) * _slot;
  int _floor(int minutes) => (minutes ~/ _slot) * _slot;

  /// Sorts the existing blocks into the ones that stay, the ones that may
  /// move and the ones that go.
  void _sortExisting(List<PlanBlock> existing, Intervals rawBusy) {
    for (final b in existing) {
      if (_existing.containsKey(b.id)) {
        throw ArgumentError('Two blocks have the id ${b.id}');
      }
      final s = _minutes(b.start, 'block.start');
      final e = _minutes(b.end, 'block.end');
      if (e <= s) throw ArgumentError('Block ${b.id} ends before it starts');
      _existing[b.id] = b;
      _ids.add(b.id);

      final isTask = b.kind == PlanBlockKind.task;
      final known = isTask
          ? _tasksById.containsKey(b.itemId)
          : _habitsById.containsKey(b.itemId);

      void settle(PlanBlock block, {required bool fixed}) {
        _settled.add(block);
        if (!known) return;
        if (isTask) {
          final day = _dayOf(s);
          _dayLoad[day] = (_dayLoad[day] ?? 0) + (e - s);
          ((_taskDays[b.itemId] ??= {})[day] ??= []).add((s, e));
          final sums = fixed ? _fixedMinutes : _doneMinutes;
          sums[b.itemId] = (sums[b.itemId] ?? 0) + (e - s);
        } else {
          _habitDaysTaken.add('${b.itemId}|${_dayOf(s)}');
        }
        if (fixed) {
          _occupied.add(s, e + (isTask ? settings.breakAfterBlocks : 0));
        }
      }

      if (b.done) {
        // History: kept even when its task is finished or gone.
        settle(b.copyWith(reason: PlanReason.done), fixed: false);
        continue;
      }
      if (!known) continue; // The task or habit is gone: so is the block.

      if (e <= _now) {
        if (settings.pastBlocks == PastBlocks.countAsDone) {
          settle(
            b.copyWith(done: true, reason: PlanReason.done),
            fixed: false,
          );
        } else if (_dayOf(e - 1) == _today) {
          settle(b.copyWith(reason: PlanReason.awaitingAnswer), fixed: true);
        }
        // Else: unanswered since an earlier day. Its time is planned again.
        continue;
      }
      if (s <= _now) {
        settle(b.copyWith(reason: PlanReason.inProgress), fixed: true);
      } else if (b.locked) {
        if (!rawBusy.isFree(s, e)) _conflicts.add(b.id);
        settle(b.copyWith(reason: PlanReason.locked), fixed: true);
      } else if (s < _now + settings.freezeMinutes) {
        settle(b.copyWith(reason: PlanReason.startingSoon), fixed: true);
      } else {
        (_movable[b.itemId] ??= []).add(_Old(b, s, e));
      }
    }
    for (final list in _movable.values) {
      list.sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.block.id.compareTo(b.block.id);
      });
    }
  }

  /// [hoursId]'s ranges on [day], as minutes, in order.
  List<(int, int)> _windowsOn(String hoursId, int day) =>
      _windows[(hoursId, day)] ??= () {
        final scheme = _hoursById[hoursId] ?? hours.first;
        final ranges = scheme.ranges[_weekdayOf(day)] ?? const <PlanRange>[];
        return [
          for (final r in ranges)
            (day * _dayMinutes + r.start, day * _dayMinutes + r.end),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
      }();

  bool _insideHours(String hoursId, int start, int end) {
    for (final (ws, we) in _windowsOn(hoursId, _dayOf(start))) {
      if (ws <= start && end <= we) return true;
    }
    return false;
  }

  /// An id nothing uses yet: [base], or [base] with a number after it.
  String _newId(String base) {
    var id = base;
    for (var n = 2; _ids.contains(id); n++) {
      id = '$base.$n';
    }
    _ids.add(id);
    return id;
  }

  static String _dayStamp(int day) {
    final d = _time(day * _dayMinutes);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  /// Puts each habit as near its ideal time as there is room, on each of
  /// its days. A habit is looked at afresh every time, so it moves back to
  /// its ideal time when that frees up.
  void _placeHabits() {
    final sorted = [...habits]..sort((a, b) {
        final c = a.order.compareTo(b.order);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    for (final h in sorted) {
      final oldByDay = <int, List<_Old>>{};
      for (final o in _movable[h.id] ?? const <_Old>[]) {
        (oldByDay[_dayOf(o.start)] ??= []).add(o);
      }
      final lengths = [
        _ceil(h.minutes),
        if (h.minMinutes != null && h.minMinutes! < h.minutes)
          _ceil(h.minMinutes!),
      ];
      for (var day = _today; day < _today + settings.horizonDays; day++) {
        if (!h.days.contains(_weekdayOf(day))) continue;
        if (_habitDaysTaken.contains('${h.id}|$day')) continue;
        final windowStart = day * _dayMinutes + h.earliest;
        final windowEnd = day * _dayMinutes + h.latest;
        final from = _ceil(math.max(windowStart, _planStart));
        if (from + lengths.last > windowEnd) continue; // Too late today.
        final ideal = day * _dayMinutes + h.ideal;

        int? start;
        var length = 0;
        for (final l in lengths) {
          int? best;
          var bestDistance = 0;
          for (var s = from; s + l <= windowEnd; s += _slot) {
            if (h.hoursId != null && !_insideHours(h.hoursId!, s, s + l)) {
              continue;
            }
            if (!_occupied.isFree(s, s + l)) continue;
            final distance = (s - ideal).abs();
            if (best == null || distance < bestDistance) {
              best = s;
              bestDistance = distance;
            }
          }
          if (best != null) {
            start = best;
            length = l;
            break;
          }
        }
        if (start == null) {
          _skipped.add(SkippedHabit(h.id, _time(day * _dayMinutes)));
          continue;
        }
        final old = oldByDay[day];
        final id = old != null && old.isNotEmpty
            ? old.first.block.id
            : _newId('${h.id}:${_dayStamp(day)}');
        _occupied.add(start, start + length);
        _settled.add(
          PlanBlock(
            id: id,
            itemId: h.id,
            kind: PlanBlockKind.habit,
            start: _time(start),
            end: _time(start + length),
            reason: length < lengths.first
                ? PlanReason.habitShortened
                : (start - ideal).abs() < _slot
                    ? PlanReason.habitIdeal
                    : PlanReason.habitShifted,
          ),
        );
      }
    }
  }

  static int _compareTasks(PlanTask a, PlanTask b) {
    var c = a.priority.index.compareTo(b.priority.index);
    if (c != 0) return c;
    final ad = a.due;
    final bd = b.due;
    if (ad == null || bd == null) {
      if (ad != bd) return ad == null ? 1 : -1;
    } else {
      c = ad.compareTo(bd);
      if (c != 0) return c;
    }
    c = a.order.compareTo(b.order);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Places every task, in the order of [steps]. With [keep], a task's
  /// blocks stay where they are if they still fit; without, every block is
  /// placed afresh (and still gets the id of a block it replaces).
  _Outcome _attempt(List<_Step> steps, {required bool keep}) {
    final occupied = Intervals.from(_occupied);
    final dayLoad = Map<int, int>.of(_dayLoad);
    final minted = <String>{};
    final blocks = <PlanBlock>[];
    final risks = <PlanRisk>[];
    final shortfall = List<int>.filled(PlanPriority.values.length + 1, 0);
    final works = <String, _Work>{};

    void take(_Work w, int start, int end, PlanReason reason, {String? id}) {
      occupied.add(start, end + settings.breakAfterBlocks);
      final day = _dayOf(start);
      dayLoad[day] = (dayLoad[day] ?? 0) + (end - start);
      (w.days[day] ??= []).add((start, end));
      w.drafts.add(_Draft(start, end, reason, id: id));
      w.need -= end - start;
    }

    /// Starts on a task: works out what is left of it, and leaves the
    /// blocks it has where they are if they still fit.
    _Work begin(PlanTask t) {
      final maxChunk = math.max(
        _slot,
        _floor(t.maxChunk ?? settings.defaultMaxChunk),
      );
      final need = _ceil(math.max(0, t.minutes)) -
          (_doneMinutes[t.id] ?? 0) -
          t.minutesLogged -
          (_fixedMinutes[t.id] ?? 0);
      final w = _Work(
        task: t,
        maxChunk: maxChunk,
        minChunk: math.min(
          maxChunk,
          math.max(_slot, _ceil(t.minChunk ?? settings.defaultMinChunk)),
        ),
        dueAt: t.due == null ? null : _minutes(t.due!, 'task.due'),
        notBefore: t.notBefore == null
            ? _planStart
            : math.max(_planStart, _minutes(t.notBefore!, 'task.notBefore')),
        need: need <= 0 ? 0 : _ceil(need),
        days: {
          for (final e in (_taskDays[t.id] ?? const {}).entries)
            e.key: [...e.value],
        },
      );
      for (final o in _movable[t.id] ?? const <_Old>[]) {
        final day = _dayOf(o.start);
        final length = math.min(o.minutes, w.need);
        final fits = keep &&
            w.need > 0 &&
            o.minutes <= w.maxChunk &&
            o.start >= w.notBefore &&
            o.end <= _horizonEnd &&
            (w.dueAt == null || o.end <= w.dueAt!) &&
            _insideHours(t.hoursId, o.start, o.end) &&
            occupied.isFree(o.start, o.end + settings.breakAfterBlocks) &&
            (dayLoad[day] ?? 0) + length <= settings.maxTaskMinutesPerDay;
        if (fits) {
          take(w, o.start, o.start + length, PlanReason.kept, id: o.block.id);
        } else {
          w.spare.add(o);
        }
      }
      return w;
    }

    /// The first place in `[from, to)` a block of the task can go, and its
    /// length.
    (int, int)? next(
      _Work w,
      int from,
      int to, {
      required bool relaxed,
      required bool whole,
    }) {
      // A whole block is as long as the task allows, cut so that the last
      // piece isn't shorter than the shortest block.
      var wholeLength = math.min(w.maxChunk, w.need);
      final rest = w.need - wholeLength;
      if (rest > 0 &&
          rest < w.minChunk &&
          wholeLength - (w.minChunk - rest) >= w.minChunk) {
        wholeLength -= w.minChunk - rest;
      }
      final least = whole ? wholeLength : math.min(w.minChunk, w.need);
      final lastDay = math.min(_dayOf(to - 1), _dayOf(_horizonEnd - 1));
      for (var day = _dayOf(from); day <= lastDay; day++) {
        final sameDay = w.days[day] ?? const <(int, int)>[];
        if (!relaxed && sameDay.length >= settings.maxChunksPerDay) continue;
        final room = _floor(
          settings.maxTaskMinutesPerDay - (dayLoad[day] ?? 0),
        );
        if (room < least) continue;
        Intervals? tooNear;
        if (!relaxed && settings.sameTaskGapMinutes > 0 && sameDay.isNotEmpty) {
          tooNear = Intervals();
          for (final (s, e) in sameDay) {
            tooNear.add(
              s - settings.sameTaskGapMinutes,
              e + settings.sameTaskGapMinutes,
            );
          }
        }
        for (final (ws, we) in _windowsOn(w.task.hoursId, day)) {
          final lo = math.max(ws, from);
          final hi = math.min(we, to);
          if (hi - lo < least) continue;
          // Room for the break after the block must be free too, unless
          // the block ends where the hours end.
          final pause = settings.breakAfterBlocks;
          for (final (gs, ge) in occupied.gaps(lo, hi + pause)) {
            final end = ge >= hi + pause ? hi : math.min(hi, ge - pause);
            if (end <= gs) continue;
            final parts = tooNear == null ? [(gs, end)] : tooNear.gaps(gs, end);
            for (final (ps, pe) in parts) {
              final start = _ceil(ps);
              final free = _floor(pe - start);
              var length = [w.maxChunk, w.need, free, room].reduce(math.min);
              if (length < least) continue;
              if (whole) {
                length = wholeLength;
              } else {
                // Don't leave a last piece shorter than the shortest
                // block.
                final left = w.need - length;
                if (left > 0 && left < w.minChunk) {
                  final shorter = length - (w.minChunk - left);
                  if (shorter >= w.minChunk) length = shorter;
                }
              }
              return (start, length);
            }
          }
        }
      }
      return null;
    }

    void fill(
      _Work w,
      int from,
      int to,
      PlanReason reason, {
      bool relaxed = false,
      required bool whole,
    }) {
      // Each search starts at [from] again: a shorter last piece may fit
      // somewhere an earlier, longer one did not.
      while (w.need > 0) {
        final spot = next(w, from, to, relaxed: relaxed, whole: whole);
        if (spot == null) return;
        take(w, spot.$1, spot.$1 + spot.$2, reason);
      }
    }

    /// What fits by the due date. Whole blocks first, so a task isn't cut
    /// into small pieces to start a little sooner; smaller pieces only if
    /// those don't fit; and for a due date, more blocks in a day.
    void placeOnTime(_Work w) {
      final to =
          w.dueAt == null ? _horizonEnd : math.min(w.dueAt!, _horizonEnd);
      fill(w, w.notBefore, to, PlanReason.earliest, whole: true);
      fill(w, w.notBefore, to, PlanReason.earliest, whole: false);
      if (w.need > 0 && w.dueAt != null) {
        fill(
          w,
          w.notBefore,
          to,
          PlanReason.deadline,
          relaxed: true,
          whole: false,
        );
      }
    }

    /// What is left goes after the due date.
    void placeLate(_Work w) {
      final dueAt = w.dueAt;
      if (w.need <= 0 || dueAt == null || dueAt >= _horizonEnd) return;
      final before = w.need;
      final from = math.max(w.notBefore, dueAt);
      fill(w, from, _horizonEnd, PlanReason.late, whole: true);
      fill(w, from, _horizonEnd, PlanReason.late, whole: false);
      w.late = before - w.need;
    }

    /// Reports the task if it doesn't fit, and names its blocks.
    void finish(_Work w) {
      final t = w.task;
      if (w.late > 0 || w.need > 0) {
        risks.add(
          PlanRisk(
            taskId: t.id,
            due: t.due,
            minutesLate: w.late,
            minutesUnplanned: w.need,
          ),
        );
        if (w.dueAt == null) {
          shortfall[PlanPriority.values.length] += w.need;
        } else {
          shortfall[t.priority.index] += w.late + w.need;
        }
      }

      // New blocks reuse the ids of the task's blocks that had to move:
      // first a block that lands exactly where one was, then in order.
      final unnamed = [
        for (final d in w.drafts)
          if (d.id == null) d,
      ]..sort((a, b) => a.start.compareTo(b.start));
      for (final d in unnamed) {
        final i =
            w.spare.indexWhere((o) => o.start == d.start && o.end == d.end);
        if (i >= 0) d.id = w.spare.removeAt(i).block.id;
      }
      for (final d in unnamed) {
        if (d.id != null) continue;
        if (w.spare.isNotEmpty) {
          d.id = w.spare.removeAt(0).block.id;
          continue;
        }
        var n = 0;
        while (_ids.contains('${t.id}:$n') || minted.contains('${t.id}:$n')) {
          n++;
        }
        d.id = '${t.id}:$n';
        minted.add(d.id!);
      }
      for (final d in w.drafts) {
        blocks.add(
          PlanBlock(
            id: d.id!,
            itemId: t.id,
            kind: PlanBlockKind.task,
            start: _time(d.start),
            end: _time(d.end),
            reason: d.reason,
          ),
        );
      }
    }

    for (final step in steps) {
      final w = works[step.task.id] ??= begin(step.task);
      if (step.stage != _Stage.late) placeOnTime(w);
      if (step.stage != _Stage.onTime) {
        placeLate(w);
        finish(w);
      }
    }
    return _Outcome(steps, blocks, risks, shortfall);
  }

  PlanResult run() {
    // The order tasks are placed in is worked out as if no block had been
    // placed yet, so it depends only on what there is to plan, never on
    // where an earlier plan happened to put things. That is what makes
    // planning again from a plan's own blocks change nothing.
    var best = _attempt(
      [
        for (final t in [...tasks]..sort(_compareTasks)) _Step(t, _Stage.all),
      ],
      keep: false,
    );

    // A task that would be late may take the time it needs by its due date
    // ahead of tasks that are due later or never, if that leaves nothing
    // more important worse off. Whatever of it is late all the same still
    // waits its turn.
    final tried = <String>{};
    for (var i = 0; i < _maxRepairs; i++) {
      final late = {
        for (final r in best.risks)
          if (r.due != null) r.taskId,
      };
      final at = best.steps.indexWhere(
        (s) =>
            s.stage == _Stage.all &&
            late.contains(s.task.id) &&
            !tried.contains(s.task.id),
      );
      if (at < 0) break;
      final task = best.steps[at].task;
      tried.add(task.id);
      final ahead = best.steps.take(at).toList().indexWhere(
            (s) =>
                s.stage != _Stage.late &&
                (s.task.due == null || s.task.due!.isAfter(task.due!)),
          );
      if (ahead < 0) continue;
      final steps = [...best.steps]
        ..[at] = _Step(task, _Stage.late)
        ..insert(ahead, _Step(task, _Stage.onTime));
      final outcome = _attempt(steps, keep: false);
      if (outcome.betterThan(best)) best = outcome;
    }

    // Now the same order with the blocks that exist left where they are.
    // That plan is the answer unless leaving them costs a due date, in
    // which case everything is placed afresh.
    final hasBlocks = tasks.any((t) => _movable.containsKey(t.id));
    if (!rebuild && hasBlocks) {
      final kept = _attempt(best.steps, keep: true);
      if (!best.betterThan(kept)) best = kept;
    }

    final blocks = [..._settled, ...best.blocks]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final planned = {for (final b in blocks) b.id};
    return PlanResult(
      blocks: blocks,
      create: [
        for (final b in blocks)
          if (!_existing.containsKey(b.id)) b,
      ],
      update: [
        for (final b in blocks)
          if (_existing[b.id] case final old? when !old.sameAs(b)) b,
      ],
      delete: [
        for (final id in _existing.keys)
          if (!planned.contains(id)) id,
      ],
      risks: best.risks,
      skippedHabits: _skipped,
      conflicts: _conflicts,
    );
  }
}
