/// The planner behind ZT Calendar's Planner: it fits tasks and habits into
/// free time around a calendar's events and says what to change.
///
/// Pure Dart and deterministic: the same inputs always give the same plan.
/// Nothing here stores, syncs or shows anything; the app does that.
library;

export 'src/model.dart';
export 'src/planner.dart' show plan;
