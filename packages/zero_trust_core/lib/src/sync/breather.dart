import 'dart:async';

import '../platform/zt_platform.dart';

/// Gives the screen a turn during long work on the UI isolate.
///
/// Sealing, signing, checking and decrypting items is pure Dart, and the
/// local store is synchronous, so a sync of a few hundred items, or an
/// import that saves them one after another, would otherwise run in one
/// piece: no frame is drawn, no tap is handled, and the system shows "isn't
/// responding". A breather lets the event loop run whenever a [slice] of
/// such work has passed, so frames and taps fit in between.
///
/// Off under `flutter test`, where the fake clock never fires the timer the
/// pause waits for; pass [enabled] or [pause] to test it.
class Breather {
  Breather({
    this.slice = const Duration(milliseconds: 8),
    this.idleGap = const Duration(milliseconds: 50),
    this.burst = 8,
    bool? enabled,
    Future<void> Function()? pause,
  })  : enabled = enabled ?? (pause != null || !ztInFlutterTest),
        _pause = pause ?? _nextEvent;

  /// How long work may run before the screen gets its turn: half a frame at
  /// 60 Hz.
  final Duration slice;

  /// Calls to [enter] further apart than this are separate pieces of work,
  /// not one run: the event loop ran in between.
  final Duration idleGap;

  /// How many [enter] calls in a row make a run worth interrupting. A screen
  /// that saves two or three items is left alone.
  final int burst;

  final bool enabled;
  final Future<void> Function() _pause;
  final Stopwatch _clock = Stopwatch()..start();

  int _sliceStart = 0;
  int _lastEnd = 0;
  int _run = 0;

  static Future<void> _nextEvent() => Future<void>.delayed(Duration.zero);

  /// Marks the start of a loop whose every pass calls [step].
  void start() => _sliceStart = _clock.elapsedMicroseconds;

  /// Inside a loop: the pause to wait for when a [slice] has passed since
  /// the last pause (or [start]), else null.
  ///
  /// Null rather than a finished future, so that work which needs no pause
  /// runs exactly as it would without a breather, with no extra turn of
  /// the microtask queue: `if (breather.step() case final pause?) await
  /// pause;`.
  Future<void>? step() {
    if (!enabled) return null;
    if (_clock.elapsedMicroseconds - _sliceStart < slice.inMicroseconds) {
      return null;
    }
    return _paused();
  }

  /// Before one piece of work that callers may repeat without a loop the
  /// breather can see (saving items one by one): the pause to wait for when
  /// [burst] or more of them have run back to back for a [slice], else
  /// null. Call [leave] after the work.
  Future<void>? enter() {
    if (!enabled) return null;
    final now = _clock.elapsedMicroseconds;
    if (now - _lastEnd > idleGap.inMicroseconds) {
      _run = 0;
      _sliceStart = now;
    }
    _run++;
    if (_run < burst || now - _sliceStart < slice.inMicroseconds) return null;
    return _paused();
  }

  Future<void> _paused() async {
    await _pause();
    _sliceStart = _clock.elapsedMicroseconds;
  }

  void leave() => _lastEnd = _clock.elapsedMicroseconds;
}
