# zt_scheduler

The planner behind ZT Calendar's Planner. It fits tasks and habits into the
free time around a calendar's events and says which blocks to add, move and
remove.

- **On the device.** Pure Dart, no Flutter, no network, no AI. Nothing
  leaves the phone to make a plan.
- **Deterministic.** The same inputs always give the same plan, whatever
  order the lists are in, so two devices that see the same data agree.
- **Calm.** Planning again from a plan's own blocks changes nothing. A
  block stays where it is unless it has to move, and a block that moves
  keeps its id, so the app updates one event instead of deleting and
  adding.

It only plans. Storing blocks as events, syncing them, showing them and
asking "did you do this?" are the app's job.

## Use

```dart
import 'package:zt_scheduler/zt_scheduler.dart';

final result = plan(
  now: PlanTime.wall(DateTime.now()),
  hours: [
    PlanHours.sameEachDay(
      'work',
      days: {1, 2, 3, 4, 5},
      ranges: const [PlanRange.hm(9, 0, 17, 0)],
    ),
  ],
  busy: [PlanBusy(meetingStart, meetingEnd)],      // the calendar's events
  habits: [lunch],
  tasks: [
    PlanTask(id: 'report', minutes: 240, due: tuesdayEvening),
    const PlanTask(id: 'slides', minutes: 90, priority: PlanPriority.high),
  ],
  existing: blocksFromLastTime,                    // the Planner's own events
);

for (final b in result.create) { /* add an event with id b.id */ }
for (final b in result.update) { /* move event b.id to b.start..b.end */ }
for (final id in result.delete) { /* remove event id */ }
```

`example/zt_scheduler_example.dart` is a runnable week:

```
Mon 09:00-09:30  expenses earliest
Mon 12:30-13:00  lunch    habitIdeal
Mon 13:00-14:30  slides   earliest
Mon 14:30-16:30  report   earliest
Tue 09:00-11:00  report   earliest
Tue 12:30-13:00  lunch    habitIdeal
```

### Times

Every time is a wall-clock time carried as a UTC `DateTime`: "Monday 09:00"
is `DateTime.utc(2026, 11, 23, 9)` in every time zone. Convert with
`PlanTime.wall(local)` on the way in and `PlanTime.local(wall)` on the way
out. A `DateTime` that is not UTC throws `ArgumentError`, so a missed
conversion fails loudly instead of planning at the wrong hour.

### What goes in

| Input | What it is |
|---|---|
| `hours` | When each kind of work may be planned (`work`, `personal`), per weekday |
| `busy` | Events. `buffered: false` for things that are busy but not meetings |
| `tasks` | Length, priority, optional due date and start date, block sizes, which hours |
| `habits` | Routines with an ideal time and a window: "lunch around 12:30, between 11:30 and 14:00" |
| `existing` | The blocks from earlier plans, with `locked` and `done` as the user set them |
| `settings` | Grid, days ahead, breaks, limits per day (`PlanSettings`) |

### What comes out

| Output | What it is |
|---|---|
| `blocks` | The whole plan, soonest first, each with a `reason` the app can turn into a sentence |
| `create`, `update`, `delete` | What to change to get there |
| `risks` | Tasks that end after their due date or don't fit, most important first |
| `skippedHabits` | Habit days that found no room |
| `conflicts` | Locked blocks that overlap an event (kept: the user chose the time) |

## The rules

1. Blocks that are done, locked, happening now, starting within
   `freezeMinutes` (30) or waiting for an answer today stay exactly as they
   are. Nothing new starts sooner than that either, so the user always gets
   some notice.
2. Habits take the free time nearest their ideal time. A habit that doesn't
   fit is shortened to its `minMinutes`, or skipped that day.
3. Tasks follow, most important first, then nearest due date. A task keeps
   the blocks it has if they still fit. What is left goes into the earliest
   free time in its hours, in whole blocks where they fit and shorter pieces
   only where they don't. A more important task doesn't wait behind the
   blocks of a lesser one: it takes the time and the lesser block moves.
4. A task that can't finish by its due date may use more blocks in a day
   than usual. If that isn't enough, the part that can still make the due
   date may go ahead of tasks that are due later or never, as long as
   nothing more important ends up worse off. What still doesn't fit is
   planned after the due date and reported.
5. Blocks are only left where they are while that costs no due date.

`plan(rebuild: true)` forgets where the movable blocks are and places them
afresh, as early as they fit ("tidy up my week"). They keep their ids.

### Blocks whose time has passed

A block that ended today without an answer waits (`awaitingAnswer`) and
still counts toward its task. From the next day its time goes back to the
task and is planned again. With `PastBlocks.countAsDone` it counts as done
instead.

### As time passes

A plan in which everything fits stays as it is. A plan that is short of
time (something in `risks`) may be rearranged as the day goes on, because
which task should give way can change.

## Tests

```sh
dart pub get && dart test
```

- `test/tasks_test.dart`, `test/existing_blocks_test.dart`,
  `test/habits_test.dart`: one named scenario per rule. These are the
  planner's specification; a change in behavior shows up as a changed
  scenario.
- `test/properties_test.dart`: hundreds of made-up calendars, each checked
  against the rules (nothing on an event, in the past, outside its hours or
  over the daily limit; every minute planned or reported), planned twice to
  see nothing changes, planned later in the day and days later, and planned
  with the inputs shuffled.
