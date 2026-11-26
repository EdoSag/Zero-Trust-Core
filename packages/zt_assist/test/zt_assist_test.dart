import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zt_assist/testing.dart';
import 'package:zt_assist/zt_assist.dart';

/// Plays the plugin's Android code: records what the Dart side sends and
/// lets a test send events back.
class FakePhone {
  FakePhone(this.channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final reply = onCall?.call(call);
      if (reply is Future) return await reply;
      return reply;
    });
  }

  final MethodChannel channel;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? onCall;

  List<String> get methods => [for (final call in calls) call.method];

  /// The id the Dart side gave its latest request of [method].
  String idOf(String method) =>
      (calls.lastWhere((c) => c.method == method).arguments as Map)['id']
          as String;

  Future<void> send(Map<String, Object?> event) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', event),
      ),
      (_) {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePhone phone;
  late MethodChannelZtAssist assist;

  setUp(() {
    const channel = MethodChannel('dev.sagron.zt_assist');
    phone = FakePhone(channel)
      ..onCall = (call) => call.method == 'installed' ? 'ready' : null;
    assist = MethodChannelZtAssist(
      channel: channel,
      statusTimeout: const Duration(milliseconds: 200),
    );
  });

  const summarize = ZtAssistRequest(
    task: ZtAssistTask.summarize,
    text: 'Notes from the building meeting',
  );

  group('asking', () {
    test('the request goes out and the answer comes back in pieces', () async {
      final events = <ZtAssistEvent>[];
      final finished = assist.ask(summarize).forEach(events.add);
      await pumpEventQueue();

      final sent = phone.calls.single;
      expect(sent.method, 'ask');
      expect(sent.arguments, {
        'id': phone.idOf('ask'),
        'task': 'summarize',
        'text': 'Notes from the building meeting',
        'instruction': null,
        'language': null,
        'maxTokens': null,
      });

      final id = phone.idOf('ask');
      await phone.send({'id': id, 'type': 'chunk', 'text': 'Door'});
      await phone.send({'id': id, 'type': 'chunk', 'text': ' replaced'});
      await phone.send({
        'id': id,
        'type': 'done',
        'stopped': false,
        'truncated': true,
        'tokens': 30,
        'milliseconds': 2500,
        'firstMilliseconds': 500,
      });
      await finished;

      expect(events.whereType<ZtAssistChunk>().map((c) => c.text), [
        'Door',
        ' replaced',
      ]);
      final done = events.last as ZtAssistDone;
      expect(done.stopped, false);
      expect(done.truncated, true);
      expect(done.tokens, 30);
      expect(done.duration, const Duration(milliseconds: 2500));
      // 30 tokens in the 2 seconds after the first piece.
      expect(done.tokensPerSecond, 15);
      // Nothing more to stop.
      expect(phone.methods, ['ask']);
    });

    test('run gives the whole answer', () async {
      final answer = assist.run(summarize);
      await pumpEventQueue();
      final id = phone.idOf('ask');
      await phone.send({'id': id, 'type': 'chunk', 'text': ' One'});
      await phone.send({'id': id, 'type': 'chunk', 'text': ' two '});
      await phone.send({'id': id, 'type': 'done'});
      expect(await answer, 'One two');
    });

    test('every option is passed on', () async {
      unawaited(
        assist
            .run(
              const ZtAssistRequest(
                task: ZtAssistTask.translate,
                text: 'Hello',
                language: 'he',
                maxTokens: 64,
              ),
            )
            .catchError((_) => ''),
      );
      await pumpEventQueue();
      final sent = phone.calls.single.arguments as Map;
      expect(sent['task'], 'translate');
      expect(sent['language'], 'he');
      expect(sent['maxTokens'], 64);
    });

    test('two answers at once do not mix', () async {
      final first = assist.run(summarize);
      await pumpEventQueue();
      final a = phone.idOf('ask');
      final second = assist.run(summarize);
      await pumpEventQueue();
      final b = phone.idOf('ask');
      expect(a, isNot(b));

      await phone.send({'id': b, 'type': 'chunk', 'text': 'B'});
      await phone.send({'id': a, 'type': 'chunk', 'text': 'A'});
      await phone.send({'id': a, 'type': 'done'});
      await phone.send({'id': b, 'type': 'done'});
      expect(await first, 'A');
      expect(await second, 'B');
    });

    test('leaving before the end tells the model to stop', () async {
      final got = <ZtAssistEvent>[];
      final listening = assist.ask(summarize).listen(got.add);
      await pumpEventQueue();
      final id = phone.idOf('ask');
      await phone.send({'id': id, 'type': 'chunk', 'text': 'One'});
      await listening.cancel();

      expect(phone.methods, ['ask', 'cancel']);
      expect(phone.calls.last.arguments, {'id': id});
      // What still arrives for it is dropped.
      await phone.send({'id': id, 'type': 'chunk', 'text': ' two'});
      await phone.send({'id': id, 'type': 'done', 'stopped': true});
      expect(got, hasLength(1));
    });

    test('a very long text is cut before it is sent', () async {
      unawaited(
        assist
            .run(
              ZtAssistRequest(
                task: ZtAssistTask.summarize,
                text: 'a' * (MethodChannelZtAssist.maxTextLength + 500),
              ),
            )
            .catchError((_) => ''),
      );
      await pumpEventQueue();
      final sent = phone.calls.single.arguments as Map;
      expect(
        (sent['text'] as String).length,
        MethodChannelZtAssist.maxTextLength,
      );
    });

    test('each failure is told apart', () async {
      Future<ZtAssistError> errorFor(String code) async {
        Object? caught;
        final answer = assist.run(summarize).then<void>(
          (_) {},
          onError: (Object e) {
            caught = e;
          },
        );
        await pumpEventQueue();
        await phone.send({
          'id': phone.idOf('ask'),
          'type': 'failed',
          'code': code,
          'detail': 'why',
        });
        await answer;
        final exception = caught! as ZtAssistException;
        expect(exception.detail, 'why');
        return exception.error;
      }

      expect(await errorFor('not_installed'), ZtAssistError.notInstalled);
      expect(await errorFor('untrusted'), ZtAssistError.notInstalled);
      expect(await errorFor('no_model'), ZtAssistError.noModel);
      expect(await errorFor('load_failed'), ZtAssistError.loadFailed);
      expect(await errorFor('unsupported'), ZtAssistError.needsUpdate);
      expect(await errorFor('stopped'), ZtAssistError.stopped);
      expect(await errorFor('failed'), ZtAssistError.failed);
      expect(await errorFor('something new'), ZtAssistError.failed);
    });

    test('pieces that arrived before a failure are kept', () async {
      final events = <ZtAssistEvent>[];
      Object? error;
      final finished =
          assist.ask(summarize).forEach(events.add).catchError((Object e) {
        error = e;
      });
      await pumpEventQueue();
      final id = phone.idOf('ask');
      await phone.send({'id': id, 'type': 'chunk', 'text': 'Half'});
      await phone.send({'id': id, 'type': 'failed', 'code': 'stopped'});
      await finished;
      expect((events.single as ZtAssistChunk).text, 'Half');
      expect((error! as ZtAssistException).error, ZtAssistError.stopped);
    });

    test('a phone that cannot take the request fails it', () async {
      phone.onCall = (call) => throw PlatformException(code: 'boom');
      await expectLater(
        assist.run(summarize),
        throwsA(
          isA<ZtAssistException>().having(
            (e) => e.error,
            'error',
            ZtAssistError.failed,
          ),
        ),
      );
    });
  });

  group('availability', () {
    Future<ZtAssistAvailability> withStatus(
      Map<String, Object?> reply,
    ) async {
      final asked = assist.availability();
      await pumpEventQueue();
      await phone.send({'id': phone.idOf('status'), ...reply});
      return asked;
    }

    test('ready with a model on the phone', () async {
      expect(
        await withStatus({'type': 'status', 'protocol': 1, 'ready': true}),
        ZtAssistAvailability.ready,
      );
      expect(phone.methods, ['installed', 'status']);
    });

    test('installed without a model', () async {
      expect(
        await withStatus({'type': 'status', 'protocol': 1, 'ready': false}),
        ZtAssistAvailability.needsModel,
      );
    });

    test('a newer ZT Assist is fine, an older one needs an update', () async {
      expect(
        await withStatus({'type': 'status', 'protocol': 7, 'ready': true}),
        ZtAssistAvailability.ready,
      );
      expect(
        await withStatus({'type': 'status', 'protocol': 0, 'ready': true}),
        ZtAssistAvailability.needsUpdate,
      );
    });

    test('not installed, or another app under its name', () async {
      phone.onCall = (call) => 'not_installed';
      expect(await assist.isInstalled(), false);
      expect(await assist.availability(), ZtAssistAvailability.notInstalled);
      phone.onCall = (call) => 'untrusted';
      expect(await assist.isInstalled(), false);
      expect(await assist.availability(), ZtAssistAvailability.notInstalled);
      // Nothing was started.
      expect(phone.methods, everyElement('installed'));
    });

    test('no answer in time, or a failure: unavailable', () async {
      expect(await assist.availability(), ZtAssistAvailability.unavailable);
      // The unanswered question is withdrawn.
      expect(phone.methods, ['installed', 'status', 'cancel']);
      expect(phone.calls.last.arguments, {'id': phone.idOf('status')});
      expect(
        await withStatus({'type': 'failed', 'code': 'failed'}),
        ZtAssistAvailability.unavailable,
      );
      expect(
        await withStatus({'type': 'failed', 'code': 'not_installed'}),
        ZtAssistAvailability.notInstalled,
      );
    });

    test('on anything but Android nothing is asked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(await assist.isInstalled(), false);
      expect(await assist.availability(), ZtAssistAvailability.unavailable);
      await expectLater(
        assist.run(summarize),
        throwsA(isA<ZtAssistException>()),
      );
      await assist.release();
      expect(phone.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('release asks the phone to let go', () async {
    await assist.release();
    expect(phone.methods, ['release']);
  });

  group('the fake for app tests', () {
    test('answers from its script and records the request', () async {
      final fake = FakeZtAssist(answer: (_) => ['A short', ' summary']);
      expect(await fake.availability(), ZtAssistAvailability.ready);
      expect(await fake.run(summarize), 'A short summary');
      expect(fake.requests.single, same(summarize));
      expect(fake.cancelled, 0);
    });

    test('can fail, be unavailable and be cancelled', () async {
      final fake = FakeZtAssist(
        state: ZtAssistAvailability.notInstalled,
        error: ZtAssistError.noModel,
      );
      expect(await fake.isInstalled(), false);
      await expectLater(
        fake.run(summarize),
        throwsA(isA<ZtAssistException>()),
      );

      final gate = Completer<void>();
      final slow = FakeZtAssist(beforePiece: () => gate.future);
      final listening = slow.ask(summarize).listen((_) {});
      await pumpEventQueue();
      await listening.cancel();
      gate.complete();
      expect(slow.cancelled, 1);
    });
  });

  test('the numbers match the service in Zero-Trust-Assist', () {
    // AssistService.java and ZtAssistPlugin.java share these by hand; this
    // pins the Dart side's view of the contract.
    expect(MethodChannelZtAssist.protocol, 1);
    expect(ZtAssist.androidPackage, 'dev.sagron.zerotrustassist');
    expect(ZtAssistTask.values.map((t) => t.name), [
      'summarize',
      'rewrite',
      'proofread',
      'translate',
      'title',
      'ask',
    ]);
  });
}
