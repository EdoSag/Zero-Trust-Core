/// A stand-in for ZT Assist, for an app's own tests.
///
/// ```dart
/// ZtAssist.instance = FakeZtAssist(answer: (_) => ['A short', ' summary']);
/// ```
library;

import 'dart:async';

import 'zt_assist.dart';

/// Answers from a script, with no phone and no model.
class FakeZtAssist extends ZtAssist {
  FakeZtAssist({
    this.state = ZtAssistAvailability.ready,
    this.answer = _hello,
    this.error,
    this.done = const ZtAssistDone(),
    this.beforePiece,
  });

  static List<String> _hello(ZtAssistRequest request) => const [
        'Hello',
        ' there',
      ];

  /// What [availability] says.
  ZtAssistAvailability state;

  /// The pieces of the answer to a request.
  List<String> Function(ZtAssistRequest request) answer;

  /// When set, every request fails with it after its pieces.
  ZtAssistError? error;

  /// How an answer ends.
  ZtAssistDone done;

  /// Waited for before each piece, so a test can look at a half-written
  /// answer.
  Future<void> Function()? beforePiece;

  /// Every request asked, in order.
  final List<ZtAssistRequest> requests = [];

  /// How many answers were cancelled before their end.
  int cancelled = 0;
  int released = 0;

  @override
  Future<bool> isInstalled() async =>
      state != ZtAssistAvailability.notInstalled &&
      state != ZtAssistAvailability.unavailable;

  @override
  Future<ZtAssistAvailability> availability() async => state;

  @override
  Stream<ZtAssistEvent> ask(ZtAssistRequest request) {
    requests.add(request);
    var stopped = false;
    late final StreamController<ZtAssistEvent> controller;
    controller = StreamController<ZtAssistEvent>(
      onListen: () async {
        for (final piece in answer(request)) {
          await beforePiece?.call();
          if (stopped) return;
          controller.add(ZtAssistChunk(piece));
        }
        final failure = error;
        if (failure != null) {
          controller.addError(ZtAssistException(failure));
        } else {
          controller.add(done);
        }
        stopped = true;
        await controller.close();
      },
      onCancel: () {
        if (!stopped) cancelled++;
        stopped = true;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> release() async => released++;
}
