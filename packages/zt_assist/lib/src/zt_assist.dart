import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A job ZT Assist can do with a text.
enum ZtAssistTask {
  /// A few short bullet points.
  summarize,

  /// The same meaning, clearer.
  rewrite,

  /// Spelling, grammar and punctuation only.
  proofread,

  /// Into [ZtAssistRequest.language]; left out, Hebrew goes to English and
  /// anything else to Hebrew.
  translate,

  /// A title of six words at most.
  title,

  /// The app's own instruction, in [ZtAssistRequest.instruction].
  ask,
}

/// One request to ZT Assist.
class ZtAssistRequest {
  const ZtAssistRequest({
    required this.task,
    required this.text,
    this.instruction,
    this.language,
    this.maxTokens,
  }) : assert(
          task != ZtAssistTask.ask || instruction != null,
          'ZtAssistTask.ask needs an instruction',
        );

  final ZtAssistTask task;

  /// The text to work on. ZT Assist uses about the first 6,000 letters
  /// (2,400 for rewrite, proofread and translate, whose answer is as long
  /// as the text) and says so in [ZtAssistDone.truncated].
  final String text;

  /// [ZtAssistTask.ask] only: what to do with the text, in the user's
  /// language.
  final String? instruction;

  /// [ZtAssistTask.translate] only: `he` or `en`.
  final String? language;

  /// A shorter limit on the answer than the job's own, in tokens (a Hebrew
  /// word is two or three).
  final int? maxTokens;
}

/// Whether ZT Assist can be asked right now.
enum ZtAssistAvailability {
  /// Installed, with a model on the phone.
  ready,

  /// Installed, but the user has not downloaded a model yet: send them to
  /// ZT Assist.
  needsModel,

  /// Installed, but older than this app needs: the user updates ZT Assist.
  needsUpdate,

  /// Not on the phone: offer [ZtAssist.installUrl].
  notInstalled,

  /// Not Android, or ZT Assist did not answer.
  unavailable,
}

/// Why a request ended without an answer.
enum ZtAssistError {
  /// ZT Assist is not on the phone.
  notInstalled,

  /// No model is on the phone: the user opens ZT Assist and downloads one.
  noModel,

  /// The model did not load, most often for lack of free memory.
  loadFailed,

  /// ZT Assist is older than this request needs.
  needsUpdate,

  /// ZT Assist stopped in the middle (the phone took its memory back).
  stopped,

  /// Anything else.
  failed,
}

class ZtAssistException implements Exception {
  const ZtAssistException(this.error, [this.detail]);

  final ZtAssistError error;

  /// The engine's own words, for a log; not for the user.
  final String? detail;

  @override
  String toString() =>
      'ZtAssistException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// What an answer is made of: [ZtAssistChunk]s, then one [ZtAssistDone].
sealed class ZtAssistEvent {
  const ZtAssistEvent();
}

/// The next piece of the answer, to append to what came before.
class ZtAssistChunk extends ZtAssistEvent {
  const ZtAssistChunk(this.text);

  final String text;
}

/// The answer is complete.
class ZtAssistDone extends ZtAssistEvent {
  const ZtAssistDone({
    this.stopped = false,
    this.truncated = false,
    this.tokens = 0,
    this.duration = Duration.zero,
    this.timeToFirstPiece = Duration.zero,
  });

  /// It was stopped before its end; what arrived is all there is.
  final bool stopped;

  /// The text was longer than the model can take, so only its beginning
  /// was used. Worth telling the user.
  final bool truncated;

  /// Length of the answer, in tokens.
  final int tokens;

  /// From the request to the end of the answer, inside ZT Assist.
  final Duration duration;

  /// How long the model read before it started to write.
  final Duration timeToFirstPiece;

  /// Writing speed, or null when the answer was too short to tell.
  double? get tokensPerSecond {
    final writing = duration - timeToFirstPiece;
    if (tokens < 2 || writing.inMilliseconds <= 0) return null;
    return tokens * 1000 / writing.inMilliseconds;
  }
}

/// The way to ZT Assist. Use [instance].
abstract class ZtAssist {
  /// The one every app uses. Tests put a fake here.
  static ZtAssist instance = MethodChannelZtAssist();

  /// ZT Assist's Android package.
  static const String androidPackage = 'dev.sagron.zerotrustassist';

  /// Where to get ZT Assist.
  static final Uri installUrl = Uri.parse(
    'https://zerotrust.bz/install/#assist',
  );

  /// Whether ZT Assist is on the phone. Quick: nothing is started. Use it
  /// to decide whether to show an "Ask ZT Assist" button at all.
  Future<bool> isInstalled();

  /// Whether ZT Assist can answer now. Starts ZT Assist in the background
  /// (not its model), so it takes a moment the first time.
  Future<ZtAssistAvailability> availability();

  /// Asks. The answer arrives piece by piece and ends with a
  /// [ZtAssistDone]; a failure arrives as a [ZtAssistException] error.
  /// Cancelling the subscription stops the model.
  ///
  /// The first answer after a while takes a few seconds longer: the model
  /// is loaded. It then stays in memory for two minutes after the last
  /// answer.
  Stream<ZtAssistEvent> ask(ZtAssistRequest request);

  /// The whole answer in one piece.
  Future<String> run(ZtAssistRequest request) async {
    final answer = StringBuffer();
    await for (final event in ask(request)) {
      if (event is ZtAssistChunk) answer.write(event.text);
    }
    return answer.toString().trim();
  }

  /// Lets ZT Assist give the model's memory back now and not in two
  /// minutes. Does nothing while an answer is on its way.
  Future<void> release();
}

/// [ZtAssist] over the plugin's Android code.
class MethodChannelZtAssist extends ZtAssist {
  MethodChannelZtAssist({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting this.statusTimeout = const Duration(seconds: 40),
  }) : _channel = channel ?? const MethodChannel('dev.sagron.zt_assist') {
    _channel.setMethodCallHandler(_onCall);
  }

  /// The version of the messages this package speaks. ZT Assist says its
  /// own in every status; one that is lower needs an update.
  static const int protocol = 1;

  /// The most text sent across, in UTF-16 units. Twice what ZT Assist
  /// uses, so it still sees that the text was cut, and far below what
  /// Android lets one message carry.
  static const int maxTextLength = 12000;

  final MethodChannel _channel;

  /// How long ZT Assist may take to say whether it is ready. Its first
  /// start in a while is the slow one.
  final Duration statusTimeout;

  final Map<String, StreamController<ZtAssistEvent>> _answers = {};
  final Map<String, Completer<Map<Object?, Object?>>> _statuses = {};
  int _next = 0;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _newId() => 'r${_next++}';

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'event') return null;
    final event = (call.arguments as Map<Object?, Object?>);
    final id = event['id'] as String?;
    final type = event['type'];

    final status = _statuses.remove(id);
    if (status != null) {
      status.complete(event);
      return null;
    }

    final answer = _answers[id];
    if (answer == null) return null; // Cancelled, or not ours.
    switch (type) {
      case 'chunk':
        answer.add(ZtAssistChunk(event['text'] as String? ?? ''));
      case 'done':
        _answers.remove(id);
        answer.add(
          ZtAssistDone(
            stopped: event['stopped'] == true,
            truncated: event['truncated'] == true,
            tokens: event['tokens'] as int? ?? 0,
            duration: Duration(
              milliseconds: event['milliseconds'] as int? ?? 0,
            ),
            timeToFirstPiece: Duration(
              milliseconds: event['firstMilliseconds'] as int? ?? 0,
            ),
          ),
        );
        unawaited(answer.close());
      case 'failed':
        _answers.remove(id);
        answer.addError(
          ZtAssistException(
            _errorOf(event['code'] as String?),
            event['detail'] as String?,
          ),
        );
        unawaited(answer.close());
    }
    return null;
  }

  static ZtAssistError _errorOf(String? code) => switch (code) {
        // Something else holds ZT Assist's name: to the user, it is not there.
        'not_installed' || 'untrusted' => ZtAssistError.notInstalled,
        'no_model' => ZtAssistError.noModel,
        'load_failed' => ZtAssistError.loadFailed,
        'unsupported' => ZtAssistError.needsUpdate,
        'stopped' => ZtAssistError.stopped,
        _ => ZtAssistError.failed,
      };

  @override
  Future<bool> isInstalled() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<String>('installed') == 'ready';
    } on Object {
      return false;
    }
  }

  @override
  Future<ZtAssistAvailability> availability() async {
    if (!_android) return ZtAssistAvailability.unavailable;
    if (!await isInstalled()) return ZtAssistAvailability.notInstalled;
    final id = _newId();
    final reply = Completer<Map<Object?, Object?>>();
    _statuses[id] = reply;
    try {
      await _channel.invokeMethod<void>('status', {'id': id});
      final status = await reply.future.timeout(statusTimeout);
      if (status['type'] != 'status') {
        return _errorOf(status['code'] as String?) == ZtAssistError.notInstalled
            ? ZtAssistAvailability.notInstalled
            : ZtAssistAvailability.unavailable;
      }
      if ((status['protocol'] as int? ?? 0) < protocol) {
        return ZtAssistAvailability.needsUpdate;
      }
      return status['ready'] == true
          ? ZtAssistAvailability.ready
          : ZtAssistAvailability.needsModel;
    } on Object {
      // No answer in time. The question is withdrawn, so it does not keep
      // the connection to ZT Assist open.
      unawaited(
        _channel
            .invokeMethod<void>('cancel', {'id': id}).catchError((Object _) {}),
      );
      return ZtAssistAvailability.unavailable;
    } finally {
      _statuses.remove(id);
    }
  }

  @override
  Stream<ZtAssistEvent> ask(ZtAssistRequest request) {
    final id = _newId();
    late final StreamController<ZtAssistEvent> controller;
    controller = StreamController<ZtAssistEvent>(
      onListen: () async {
        if (!_android) {
          controller.addError(
            const ZtAssistException(ZtAssistError.notInstalled),
          );
          await controller.close();
          return;
        }
        _answers[id] = controller;
        final text = request.text.length > maxTextLength
            ? request.text.substring(0, maxTextLength)
            : request.text;
        try {
          await _channel.invokeMethod<void>('ask', {
            'id': id,
            'task': request.task.name,
            'text': text,
            'instruction': request.instruction,
            'language': request.language,
            'maxTokens': request.maxTokens,
          });
        } on Object catch (error) {
          if (_answers.remove(id) == null) return;
          controller.addError(
            ZtAssistException(ZtAssistError.failed, '$error'),
          );
          await controller.close();
        }
      },
      onCancel: () async {
        // Still open: the listener left before the end, so the model is
        // told to stop writing.
        if (_answers.remove(id) == null) return;
        try {
          await _channel.invokeMethod<void>('cancel', {'id': id});
        } on Object {
          // ZT Assist is gone; there is nothing to stop.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> release() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on Object {
      // Nothing was connected.
    }
  }
}
