import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

class _GatedSink implements ZtCrashReportSink {
  _GatedSink(this.gate);
  final Completer<void> gate;
  final sent = <ZtCrashReport>[];

  @override
  Future<void> send(ZtCrashReport report) async {
    await gate.future;
    sent.add(report);
  }
}

class FakeSink implements ZtCrashReportSink {
  final sent = <ZtCrashReport>[];
  bool fail = false;

  @override
  Future<void> send(ZtCrashReport report) async {
    if (fail) throw Exception('offline');
    sent.add(report);
  }
}

final _stack = StackTrace.fromString('''
#0      NoteEditor.save (package:zt_notes/editor/note_editor.dart:120:7)
#1      _NoteEditorState.build.<anonymous closure> (package:zt_notes/editor/note_editor.dart:88:15)
#2      main (file:///home/edo/dev/zt_notes/lib/main.dart:10:3)
#3      _RootZone.runUnary (dart:async/zone.dart:1415:54)
#4      something nobody can parse edo@example.com
''');

void main() {
  final now = DateTime.utc(2026, 11, 11, 14, 37, 12);

  ZtCrashReport build(Object error, {StackTrace? stack}) =>
      ZtCrashScrubber.build(
        error: error,
        stack: stack ?? _stack,
        appId: 'notes',
        appVersion: '0.4.1+12',
        platform: 'android',
        now: now,
        id: 'local',
      );

  group('scrubber', () {
    test('keeps code locations, drops file paths and unknown lines', () {
      final r = build(StateError('x'));
      expect(r.frames, [
        'NoteEditor.save (package:zt_notes/editor/note_editor.dart:120:7)',
        '_NoteEditorState.build.<anonymous closure> '
            '(package:zt_notes/editor/note_editor.dart:88:15)',
        'main',
        '_RootZone.runUnary (dart:async/zone.dart:1415:54)',
      ]);
      expect(r.toText(), isNot(contains('edo')));
      expect(r.day, '2026-11-11');
      expect(r.toText(), isNot(contains('14:37')));
    });

    test('release frames keep the virtual address only', () {
      final r = build(
        StateError('x'),
        stack: StackTrace.fromString(
          '#00 abs 0000007a1b2c3d4e virt 00000000002c3d4e '
          '_kDartIsolateSnapshotInstructions+0x1234\n',
        ),
      );
      expect(r.frames, [
        'virt 00000000002c3d4e _kDartIsolateSnapshotInstructions+0x1234',
      ]);
    });

    test('exceptions that can quote input never keep their message', () {
      final r = build(const FormatException('Bad date "my secret note"'));
      expect(r.errorType, 'FormatException');
      expect(r.message, isNull);
      expect(build(Exception('call 0521234567')).message, isNull);
    });

    test('only the runtime\'s own message templates are kept', () {
      // Code can build a StateError from anything, including user text.
      expect(build(StateError('Patient Alice Smith')).message, isNull);
      expect(build(StateError("'Alice Smith'")).message, isNull);
      expect(build(UnsupportedError('note: buy milk')).message, isNull);
      expect(
        build(RangeError.index(5, [1, 2, 3])).message,
        contains('Index out of range'),
      );
      expect(
        build(RangeError.range(7, 0, 3, 'day')).message,
        'RangeError (day): Invalid value: Not in inclusive range 0..3: 7',
      );
      expect(build(RangeError('Alice Smith')).message, isNull);
      expect(
        build(RangeError.value(1234567)).message,
        'RangeError: Value not in range: <number>',
      );
      Object? cast;
      try {
        cast = (null as dynamic) as String;
      } on TypeError catch (e) {
        cast = e;
      }
      expect(
        build(cast).message,
        "type 'Null' is not a subtype of type 'String' in type cast",
      );
    });

    test('quoted text only survives when it looks like a type', () {
      expect(
        ZtCrashScrubber.message(
          "type 'Map<String, int>' is not a subtype of type 'String'",
        ),
        "type 'Map<String, int>' is not a subtype of type 'String'",
      );
      expect(
        ZtCrashScrubber.message("type 'Alice Smith' is not"),
        "type <text> is not",
      );
      expect(
        ZtCrashScrubber.message('id 0521234567 at https://x.y/z?q=1'),
        'id <number> at <link>',
      );
      expect(ZtCrashScrubber.message('mail edo@example.com'), 'mail <email>');
      // Hebrew (or any non-ASCII) text can only be user content here.
      expect(ZtCrashScrubber.message('a שלום'), 'a');
    });

    test('fingerprint is plain 64-bit FNV-1a, 16 hex digits, no sign', () {
      // Known FNV-1a 64 values; the second has the top bit set.
      expect(
        ZtCrashScrubber.fingerprintOf('a', 'b', const []),
        isNot(startsWith('-')),
      );
      expect(
        ZtCrashScrubber.fingerprintOf('zt_notes', 'StateError', const [
          'a.dart:1',
          'b.dart:2',
        ]),
        'dbab10180e6ffe86',
      );
    });

    test('same bug, same fingerprint; different place, different one', () {
      final a = build(StateError('a'));
      final b = build(StateError('b'));
      expect(a.fingerprint, b.fingerprint);
      expect(a.fingerprint, hasLength(16));
      final c = build(
        StateError('a'),
        stack: StackTrace.fromString(
          '#0      Other.place (package:zt_notes/x.dart:1:1)\n',
        ),
      );
      expect(c.fingerprint, isNot(a.fingerprint));
    });

    test('what is sent has no local id and nothing about the person', () {
      final payload = build(StateError('x')).toPayload();
      expect(payload.keys.toSet(), {
        'app',
        'version',
        'platform',
        'day',
        'type',
        'uncaught',
        'fingerprint',
        'count',
        'frames',
      });
    });

    test('saved reports round-trip', () {
      final r = build(StateError('x'));
      final back = ZtCrashReport.fromJson(
        (jsonDecode(jsonEncode(r.toJson())) as Map).cast(),
      );
      expect(back.toText(), r.toText());
      expect(back.id, r.id);
    });
  });

  group('reporter', () {
    late InMemoryPreferencesStore prefs;
    late InMemoryCrashReportStore store;
    late FakeSink sink;

    setUp(() {
      prefs = InMemoryPreferencesStore();
      store = InMemoryCrashReportStore();
      sink = FakeSink();
    });

    ZtCrashReporter reporter({bool withSink = true}) => ZtCrashReporter(
      appId: 'notes',
      appVersion: '0.4.1+12',
      sink: withSink ? sink : null,
      preferences: prefs,
      store: store,
      platform: 'android',
      now: () => now,
    );

    test('off by default: records and keeps nothing', () async {
      final r = reporter();
      await r.load();
      expect(r.mode, ZtCrashReportMode.off);
      r.record(StateError('x'), _stack);
      expect(r.reports, isEmpty);
      expect(store.saved, isEmpty);
      expect(sink.sent, isEmpty);
    });

    test('errors before load are dropped when reports are off', () async {
      final r = reporter();
      r.record(StateError('early'), _stack);
      await r.load();
      expect(r.reports, isEmpty);
    });

    test('ask: kept on the phone, counted once per bug, not sent', () async {
      prefs.values[ZtCrashReporter.prefKey] = 'ask';
      final r = reporter();
      r.record(StateError('early'), _stack);
      await r.load();
      r.record(StateError('again'), _stack);
      r.record(const FormatException('x'), _stack);
      expect(r.reports, hasLength(2));
      expect(r.reports.last.count, 2);
      expect(store.saved, hasLength(2));
      expect(sink.sent, isEmpty);

      await r.send(r.reports.first.id);
      expect(sink.sent.single.errorType, 'FormatException');
      expect(r.reports, hasLength(1));
    });

    test('keeps at most ten reports', () async {
      prefs.values[ZtCrashReporter.prefKey] = 'ask';
      final r = reporter();
      await r.load();
      for (var i = 0; i < 15; i++) {
        r.record(
          StateError('x'),
          StackTrace.fromString('#0      F$i (package:a/b.dart:1:1)\n'),
        );
      }
      expect(r.reports, hasLength(ZtCrashReporter.maxSaved));
      expect(r.reports.first.frames.single, startsWith('F14'));
    });

    test('turning reports off deletes saved ones', () async {
      prefs.values[ZtCrashReporter.prefKey] = 'ask';
      final r = reporter();
      await r.load();
      r.record(StateError('x'), _stack);
      await r.setMode(ZtCrashReportMode.off);
      expect(r.reports, isEmpty);
      expect(store.saved, isEmpty);
      expect(prefs.values[ZtCrashReporter.prefKey], 'off');
    });

    test('automatic sends, and keeps what fails for next start', () async {
      final r = reporter();
      await r.load();
      await r.setMode(ZtCrashReportMode.automatic);
      sink.fail = true;
      r.record(StateError('x'), _stack);
      await r.sendAll();
      expect(r.reports, hasLength(1));

      sink.fail = false;
      final next = reporter();
      await next.load();
      await next.sendAll();
      expect(sink.sent, hasLength(1));
      expect(next.reports, isEmpty);
      expect(store.saved, isEmpty);
    });

    test('without a destination, automatic is not possible', () async {
      prefs.values[ZtCrashReporter.prefKey] = 'automatic';
      final r = reporter(withSink: false);
      await r.load();
      expect(r.mode, ZtCrashReportMode.ask);
      expect(r.canSend, isFalse);
      expect(() => r.setMode(ZtCrashReportMode.automatic), throwsStateError);
    });

    test('turning reports off stops an upload batch under way', () async {
      final gate = Completer<void>();
      final slow = _GatedSink(gate);
      final r = ZtCrashReporter(
        appId: 'notes',
        sink: slow,
        preferences: prefs..values[ZtCrashReporter.prefKey] = 'ask',
        store: store,
        platform: 'android',
      );
      await r.load();
      for (var i = 0; i < 3; i++) {
        r.record(
          StateError('x'),
          StackTrace.fromString('#0      F$i (package:a/b.dart:1:1)\n'),
        );
      }
      final batch = r.sendAll(); // e.g. "Send" on the prompt
      await r.setMode(ZtCrashReportMode.off);
      gate.complete();
      await batch;
      expect(slow.sent, hasLength(1)); // only the one already in flight
    });

    test('the same crash during an upload is kept, not lost', () async {
      final gate = Completer<void>();
      final slow = _GatedSink(gate);
      final r = ZtCrashReporter(
        appId: 'notes',
        sink: slow,
        preferences: prefs..values[ZtCrashReporter.prefKey] = 'ask',
        store: store,
        platform: 'android',
      );
      await r.load();
      r.record(StateError('x'), _stack);
      final sending = r.send(r.reports.single.id);
      r.record(StateError('x'), _stack); // happens again meanwhile
      gate.complete();
      await sending;
      expect(slow.sent.single.count, 1);
      expect(r.reports.single.count, 1);
    });

    test('install hooks Flutter errors and keeps the old handler', () async {
      prefs.values[ZtCrashReporter.prefKey] = 'ask';
      final r = reporter();
      await r.load();
      final before = FlutterError.onError;
      var forwarded = 0;
      FlutterError.onError = (_) => forwarded++;
      addTearDown(() => FlutterError.onError = before);
      final platformBefore = WidgetsBinding.instance.platformDispatcher.onError;
      addTearDown(
        () =>
            WidgetsBinding.instance.platformDispatcher.onError = platformBefore,
      );

      r.install();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('x'),
          stack: _stack,
          library: 'widgets library',
        ),
      );
      expect(forwarded, 1);
      expect(r.reports.single.uncaught, isFalse);
      expect(r.reports.single.library, 'widgets library');
    });
  });

  test('http sink posts the payload with no account token', () async {
    late http.Request seen;
    final sink = ZtHttpCrashReportSink(
      Uri.parse('https://example.test/crash'),
      headers: {'apikey': 'public'},
      client: MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );
    final report = build(StateError('x'));
    await sink.send(report);
    expect(seen.method, 'POST');
    expect(
      seen.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(jsonDecode(seen.body), report.toPayload());

    final refusing = ZtHttpCrashReportSink(
      Uri.parse('https://example.test'),
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(() => refusing.send(report), throwsA(anything));
  });

  group('screens', () {
    late InMemoryPreferencesStore prefs;
    late FakeSink sink;
    late ZtCrashReporter reporter;

    setUp(() async {
      prefs = InMemoryPreferencesStore();
      sink = FakeSink();
      reporter = ZtCrashReporter(
        appId: 'notes',
        appVersion: '0.4.1+12',
        sink: sink,
        preferences: prefs,
        store: InMemoryCrashReportStore(),
        platform: 'android',
        now: () => now,
      );
    });

    Widget app(
      Widget home, {
      Locale? locale,
      bool withReporter = true,
      double textScale = 1,
    }) => ProviderScope(
      overrides: [
        accountServiceProvider.overrideWithValue(
          AccountService(FakeBackend(), params: fast),
        ),
        ztPreferencesStoreProvider.overrideWithValue(prefs),
        ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'),
        ),
        if (withReporter) ztCrashReporterProvider.overrideWithValue(reporter),
      ],
      child: MaterialApp(
        theme: ZtTheme.light(),
        locale: locale,
        localizationsDelegates: ZtLanguages.delegates,
        supportedLocales: ZtL10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

    testWidgets('settings row only when the app set up reports', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await reporter.load();
      await tester.pumpWidget(
        app(ZtSettingsPage(onSignedOut: () {}), withReporter: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Crash reports'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Crash reports'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      // In Security, right under "How your data is protected".
      expect(
        tester.getRect(find.text('Crash reports')).top,
        greaterThan(
          tester.getRect(find.text('How your data is protected')).bottom,
        ),
      );
      expect(
        tester.getRect(find.text('Crash reports')).bottom,
        lessThan(tester.getRect(find.text('Appearance')).top),
      );
    });

    testWidgets('turn on, read the exact report, send it', (tester) async {
      await reporter.load();
      await tester.pumpWidget(app(ZtCrashReportsScreen(reporter: reporter)));
      await tester.pumpAndSettle();
      expect(find.text('Saved reports'), findsNothing);

      await tester.tap(find.text('Ask me before sending'));
      await tester.pumpAndSettle();
      expect(prefs.values[ZtCrashReporter.prefKey], 'ask');
      expect(find.text('No saved reports'), findsOneWidget);

      reporter.record(StateError('x'), _stack);
      await tester.pumpAndSettle();
      expect(find.text('StateError'), findsOneWidget);
      await tester.tap(find.text('StateError'));
      await tester.pumpAndSettle();

      expect(find.textContaining('"fingerprint"'), findsOneWidget);
      final send = find.widgetWithText(TextButton, 'Send');
      final copy = find.widgetWithText(TextButton, 'Copy');
      final delete = find.widgetWithText(TextButton, 'Delete');
      // All three actions visible, side by side, none hiding another.
      final rs = tester.getRect(send), rc = tester.getRect(copy);
      final rd = tester.getRect(delete);
      expect(rs.overlaps(rc) || rc.overlaps(rd), isFalse);
      expect(rs.height, greaterThan(0));

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sink.sent, hasLength(1));
      expect(find.text('Report sent. Thank you!'), findsOneWidget);
      expect(find.text('No saved reports'), findsOneWidget);
    });

    testWidgets('without a destination: no automatic, no Send', (tester) async {
      final local = ZtCrashReporter(
        appId: 'notes',
        preferences: prefs,
        store: InMemoryCrashReportStore(),
        platform: 'android',
      );
      await local.load();
      await local.setMode(ZtCrashReportMode.ask);
      local.record(StateError('x'), _stack);
      await tester.pumpWidget(app(ZtCrashReportsScreen(reporter: local)));
      await tester.pumpAndSettle();
      expect(find.text('Send automatically'), findsNothing);
      expect(
        find.text('Keep on this phone so I can copy them'),
        findsOneWidget,
      );
      await tester.tap(find.text('StateError'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Send'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Copy'), findsOneWidget);
    });

    testWidgets('Hebrew, right to left, large text: lays out', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await reporter.load();
      await reporter.setMode(ZtCrashReportMode.ask);
      reporter.record(StateError('x'), _stack);
      await tester.pumpWidget(
        app(
          ZtCrashReportsScreen(reporter: reporter),
          locale: ZtLanguages.hebrew,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('דוחות קריסה'), findsOneWidget);
      // Right to left: the intro starts at the right edge of the screen.
      final intro = tester.getRect(find.textContaining('כשהאפליקציה'));
      expect(intro.right, closeTo(1080 / 3 - 16, 1));
      expect(intro.left, greaterThanOrEqualTo(16));
      await tester.scrollUntilVisible(find.text('StateError'), 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after a crash, "ask" offers to send once', (tester) async {
      await reporter.load();
      await reporter.setMode(ZtCrashReportMode.ask);
      reporter.record(StateError('x'), _stack);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    maybeAskToSendZtCrashReports(context, reporter),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('The app hit a problem'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sink.sent, hasLength(1));
      expect(reporter.reports, isEmpty);
    });
  });
}
