import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

/// S-1: builds installed from GitHub tell the person when a newer signed
/// release is out, and link to Obtainium.
void main() {
  const repo = 'EdoSag/Zero-Trust-Notes';
  const apk =
      'https://github.com/EdoSag/Zero-Trust-Notes/releases/download/v0.7.0-build1012/app-release.apk';

  Map<String, Object?> release({
    String tag = 'v0.7.0-build1012',
    List<String> apks = const ['app-release.apk'],
    String body = '- Faster search',
  }) =>
      {
        'tag_name': tag,
        'html_url': 'https://github.com/$repo/releases/tag/$tag',
        'body': body,
        'assets': [
          {'name': 'checksums.txt', 'browser_download_url': 'https://x/c.txt'},
          for (final a in apks)
            {
              'name': a,
              'browser_download_url':
                  'https://github.com/$repo/releases/download/$tag/$a',
            },
        ],
      };

  late List<http.Request> requests;
  late http.Response Function() answer;

  ZtReleaseSource source() => ZtReleaseSource(
        repo: repo,
        client: MockClient((r) async {
          requests.add(r);
          return answer();
        }),
      );

  setUp(() {
    requests = [];
    answer = () => http.Response(jsonEncode(release()), 200);
  });

  group('versions', () {
    test('tags and installed versions compare by their numbers', () {
      expect(ztVersionOf('v0.7.0-build1012'), [0, 7, 0]);
      expect(ztVersionOf('1.4.2+8'), [1, 4, 2]);
      expect(ztVersionOf('v2'), [2, 0, 0]);
      expect(ztVersionOf('latest'), isNull);
      expect(ztIsNewerVersion('v0.7.0-build1012', '0.6.9+30'), isTrue);
      expect(ztIsNewerVersion('v0.10.0-build1', '0.9.0'), isTrue,
          reason: 'numbers, not text');
      expect(ztIsNewerVersion('v0.7.0-build1013', '0.7.0+12'), isFalse,
          reason: 'only the version counts, not the build');
      expect(ztIsNewerVersion('v0.6.0', '0.7.0'), isFalse);
      expect(ztIsNewerVersion('nightly', '0.7.0'), isFalse);
    });

    test('a release picks one APK to download', () {
      expect(ZtRelease.fromGitHub(release())!.apk, Uri.parse(apk));
      final split = ZtRelease.fromGitHub(release(apks: [
        'app-armeabi-v7a-release.apk',
        'app-arm64-v8a-release.apk',
        'app-x86_64-release.apk',
      ]))!;
      expect(split.apk.toString(), endsWith('app-arm64-v8a-release.apk'));
      final none = ZtRelease.fromGitHub(release(apks: []))!;
      expect(none.apk, isNull);
      expect(none.downloadUrl, none.page, reason: 'falls back to the page');
      expect(ZtRelease.fromGitHub({'tag_name': 'x', 'html_url': 'y'}), isNull);
    });
  });

  group('release source', () {
    test('asks GitHub anonymously for the latest release only', () async {
      final latest = await source().latest();
      expect(latest!.version, '0.7.0');
      expect(latest.notes, '- Faster search');
      expect(requests.single.url.toString(),
          'https://api.github.com/repos/$repo/releases/latest');
      expect(requests.single.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
    });

    test('no release yet is not an error; a server error is', () async {
      answer = () => http.Response('{"message":"Not Found"}', 404);
      expect(await source().latest(), isNull);
      answer = () => http.Response('rate limited', 403);
      await expectLater(
          source().latest(), throwsA(isA<http.ClientException>()));
    });
  });

  group('launch notice', () {
    late InMemoryPreferencesStore prefs;
    late String installed;
    ZtUpdates updates() => ZtUpdates(
        source: source(),
        installedVersion: () async => installed,
        preferences: prefs);

    setUp(() {
      prefs = InMemoryPreferencesStore();
      installed = '0.6.0';
    });

    test('once per new version, and at most once a day', () async {
      final start = DateTime.utc(2026, 11, 22, 9);
      await withClock(Clock.fixed(start), () async {
        expect((await updates().launchNotice())!.update!.version, '0.7.0');
        expect(await updates().launchNotice(), isNull, reason: 'same day');
      });
      await withClock(Clock.fixed(start.add(const Duration(days: 1))),
          () async {
        expect(await updates().launchNotice(), isNull,
            reason: 'already told about 0.7.0');
      });
      answer = () => http.Response(jsonEncode(release(tag: 'v0.8.0')), 200);
      await withClock(Clock.fixed(start.add(const Duration(days: 2))),
          () async {
        expect((await updates().launchNotice())!.update!.version, '0.8.0');
      });
      expect(requests, hasLength(3));
    });

    test('nothing when up to date, switched off, or offline', () async {
      installed = '0.7.0';
      expect(await updates().launchNotice(), isNull);

      prefs = InMemoryPreferencesStore();
      installed = '0.6.0';
      await updates().setEnabled(false);
      expect(await updates().launchNotice(), isNull);
      expect(requests, hasLength(1), reason: 'switched off asks nobody');

      prefs = InMemoryPreferencesStore();
      answer = () => throw http.ClientException('offline');
      expect(await updates().launchNotice(), isNull);
    });

    test('Obtainium link adds this app from its GitHub repository', () {
      final url = updates().obtainiumUrl;
      expect(url.host, 'apps.obtainium.imranr.dev');
      expect(url.path, '/redirect');
      expect(url.queryParameters['r'],
          'obtainium://add/https://github.com/EdoSag/Zero-Trust-Notes');
    });
  });

  test('release repository follows the suite naming unless given', () {
    expect(
        const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes')
            .releaseRepo,
        'EdoSag/Zero-Trust-Notes');
    expect(
        const ZtAppConfig(
                appId: 'time',
                displayName: 'Zero-Trust Time',
                releaseRepo: 'EdoSag/Zero-Trust-Time')
            .releaseRepo,
        'EdoSag/Zero-Trust-Time');
  });

  group('screens', () {
    late List<Uri> opened;
    late InMemoryPreferencesStore prefs;
    late AccountService account;

    setUp(() {
      opened = [];
      prefs = InMemoryPreferencesStore();
      account = AccountService(FakeBackend(), params: fast, legacyParams: fast);
    });

    Widget app(Widget home,
            {ZtInstallChannel channel = ZtInstallChannel.direct,
            GlobalKey<NavigatorState>? navigatorKey}) =>
        ProviderScope(
          overrides: [
            accountServiceProvider.overrideWithValue(account),
            ztPreferencesStoreProvider.overrideWithValue(prefs),
            ztAppConfigProvider.overrideWithValue(ZtAppConfig(
                appId: 'notes',
                displayName: 'Zero-Trust Notes',
                channel: channel)),
            ztInstalledVersionProvider.overrideWith((ref) async => '0.6.0'),
            ztReleaseSourceProvider.overrideWithValue(source()),
            ztOpenExternalUrlProvider.overrideWithValue((url) async {
              opened.add(url);
              return true;
            }),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: ZtTheme.light(),
            localizationsDelegates: ZtLanguages.delegates,
            supportedLocales: ZtL10n.supportedLocales,
            home: home,
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> showAbout(WidgetTester tester) async {
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('zt-obtainium')), 200,
          scrollable: find.byType(Scrollable).first);
      await settle(tester);
    }

    testWidgets('settings: update row under the app, then switch, Obtainium',
        (tester) async {
      await account.signUp(
          email: 'edo@example.com', password: 'correct horse battery');
      await tester.pumpWidget(
          app(ZtSettingsPage(onSignedOut: () {}, version: '0.6.0')));
      await settle(tester);
      await showAbout(tester);

      final appRow = find.widgetWithText(ListTile, 'Zero-Trust Notes');
      final updateRow = find.byKey(const ValueKey('zt-app-updates'));
      final switchRow = find.byKey(const ValueKey('zt-check-updates'));
      final obtainium = find.byKey(const ValueKey('zt-obtainium'));
      expect(find.text('Version 0.7.0 is available. Tap to update.'),
          findsOneWidget);
      expect(tester.getTopLeft(updateRow).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(appRow).dy - 0.01));
      expect(tester.getTopLeft(switchRow).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(updateRow).dy - 0.01));
      expect(tester.getTopLeft(obtainium).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(switchRow).dy - 0.01));
      expect(tester.widget<SwitchListTile>(switchRow).value, isTrue);

      await tester.tap(obtainium);
      await settle(tester);
      expect(opened.single.host, 'apps.obtainium.imranr.dev');

      await tester.tap(updateRow);
      await settle(tester);
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Zero-Trust Notes 0.7.0 is ready. You have 0.6.0.'),
          findsOneWidget);
      expect(find.text('- Faster search'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Download'));
      await settle(tester);
      expect(opened.last, Uri.parse(apk));
      expect(find.text('Update available'), findsNothing);

      await tester.tap(switchRow);
      await settle(tester);
      expect(await prefs.read('updates_check'), 'false');
    });

    testWidgets('settings: switched off, GitHub is asked only on a tap',
        (tester) async {
      await prefs.write('updates_check', 'false');
      await tester.pumpWidget(
          app(ZtSettingsPage(onSignedOut: () {}, accountOptional: true)));
      await settle(tester);
      await showAbout(tester);
      expect(requests, isEmpty);
      final updateRow = find.byKey(const ValueKey('zt-app-updates'));
      expect(
          find.descendant(
              of: updateRow, matching: find.text('Tap to check now.')),
          findsOneWidget);
      expect(
          tester
              .widget<SwitchListTile>(
                  find.byKey(const ValueKey('zt-check-updates')))
              .value,
          isFalse);

      await tester.tap(updateRow);
      await settle(tester);
      expect(requests, hasLength(1));
      expect(find.text('Version 0.7.0 is available. Tap to update.'),
          findsOneWidget);
    });

    testWidgets('settings: up to date says so', (tester) async {
      answer = () => http.Response(jsonEncode(release(tag: 'v0.6.0')), 200);
      await tester.pumpWidget(
          app(ZtSettingsPage(onSignedOut: () {}, accountOptional: true)));
      await settle(tester);
      await showAbout(tester);
      expect(find.text('You have the latest version (0.6.0)'), findsOneWidget);
    });

    for (final store in [ZtInstallChannel.play, ZtInstallChannel.appStore]) {
      testWidgets('${store.name} builds never check or show the rows',
          (tester) async {
        await tester.pumpWidget(app(
            ZtSettingsPage(onSignedOut: () {}, accountOptional: true),
            channel: store));
        await settle(tester);
        await tester.scrollUntilVisible(find.text('Open-source licences'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const ValueKey('zt-app-updates')), findsNothing);
        expect(find.byKey(const ValueKey('zt-obtainium')), findsNothing);
        expect(requests, isEmpty);
      });
    }

    testWidgets('after unlock: told once, then not again the same version',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
          app(const Scaffold(body: Text('Home')), navigatorKey: nav));
      await settle(tester);

      ztCheckPendingDeletionAfterUnlock(nav.currentContext!, account);
      await settle(tester);
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Not now'));
      await settle(tester);
      expect(opened, isEmpty);

      // Next launch the same day, and a day later: no second notice.
      ztCheckPendingDeletionAfterUnlock(nav.currentContext!, account);
      await settle(tester);
      expect(find.text('Update available'), findsNothing);
    });
  });
}
