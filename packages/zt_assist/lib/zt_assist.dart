/// Lets a Zero-Trust app ask ZT Assist, the private AI that runs on the
/// phone, to summarize, rewrite, proofread, translate or title a text.
///
/// ```dart
/// final assist = ZtAssist.instance;
/// if (await assist.availability() == ZtAssistAvailability.ready) {
///   final answer = assist.ask(
///     const ZtAssistRequest(task: ZtAssistTask.summarize, text: noteText),
///   );
///   await for (final event in answer) {
///     if (event is ZtAssistChunk) show(event.text);
///   }
/// }
/// ```
///
/// The text goes from this app to ZT Assist inside the phone and nowhere
/// else. Tests use `FakeZtAssist` from `package:zt_assist/testing.dart`.
library;

export 'src/zt_assist.dart';
