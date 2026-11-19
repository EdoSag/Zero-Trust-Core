import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

const email = 'edo@example.com';
const password = 'correct horse battery';
const notes = ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes');
const browser = ZtCapabilities(ZtPlatformKind.web);
const phone = ZtCapabilities(ZtPlatformKind.android);

/// The web's lock policy: the password is asked on every visit unless the
/// user turns on "Remember on this browser", and a shared computer can be
/// cleaned with "Sign out and remove data from this browser". Phones and
/// desktop apps show neither.
void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late FakeBackend backend;
  late InMemorySessionKeyStore kept;
  late AccountService account;
  late InMemoryPreferencesStore prefs;
  late int wipes;
  late int signedOut;

  setUp(() {
    backend = FakeBackend();
    kept = InMemorySessionKeyStore();
    account = AccountService(backend,
        params: fast, legacyParams: fast, sessionKeys: kept);
    prefs = InMemoryPreferencesStore();
    wipes = 0;
    signedOut = 0;
  });

  Widget settings(ZtCapabilities caps) => ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider.overrideWithValue(prefs),
          ztAppConfigProvider.overrideWithValue(notes),
          ztCapabilitiesProvider.overrideWithValue(caps),
          ztBrowserWipeProvider.overrideWithValue(() async => wipes++),
        ],
        child: MaterialApp(
          theme: ZtTheme.light(),
          home: ZtSettingsPage(onSignedOut: () => signedOut++),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<String> signedIn() async {
    await account.signUp(email: email, password: password);
    return backend.currentUserId!;
  }

  Future<void> show(WidgetTester tester, ZtCapabilities caps) async {
    await tester.pumpWidget(settings(caps));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  group('capabilities', () {
    test('a browser has no phone-only features', () {
      expect(browser.isWeb, isTrue);
      expect(browser.isMobile, isFalse);
      expect(browser.isDesktop, isFalse);
      expect(browser.homeScreenWidgets, isFalse);
      expect(browser.scheduledNotifications, isFalse);
      expect(browser.biometricUnlock, isFalse);
      expect(browser.onDeviceSpeech, isFalse);
      expect(browser.onDeviceTextRecognition, isFalse);
      expect(browser.cameraScanning, isFalse);
      expect(browser.phoneIntegration, isFalse);
      expect(browser.exportsByDownload, isTrue);
      expect(browser.browserSession, isTrue);
    });

    test('a phone keeps them all, and has no browser session', () {
      for (final kind in [ZtPlatformKind.android, ZtPlatformKind.ios]) {
        final caps = ZtCapabilities(kind);
        expect(caps.isMobile, isTrue);
        expect(caps.homeScreenWidgets, isTrue);
        expect(caps.scheduledNotifications, isTrue);
        expect(caps.biometricUnlock, isTrue);
        expect(caps.onDeviceSpeech, isTrue);
        expect(caps.cameraScanning, isTrue);
        expect(caps.phoneIntegration, isTrue);
        expect(caps.exportsByDownload, isFalse);
        expect(caps.browserSession, isFalse);
      }
    });

    test('desktop apps are neither phone nor browser', () {
      for (final kind in [
        ZtPlatformKind.windows,
        ZtPlatformKind.macos,
        ZtPlatformKind.linux,
      ]) {
        final caps = ZtCapabilities(kind);
        expect(caps.isDesktop, isTrue);
        expect(caps.homeScreenWidgets, isFalse);
        expect(caps.biometricUnlock, isFalse);
        expect(caps.browserSession, isFalse);
        expect(caps.exportsByDownload, isFalse);
      }
    });

    test('the running platform is detected', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(ZtCapabilities.current().platform, ZtPlatformKind.windows);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(ZtCapabilities.current().platform, ZtPlatformKind.ios);
    });
  });

  group('settings in a browser', () {
    testWidgets('a phone shows neither browser row', (tester) async {
      await tester.runAsync(signedIn);
      await show(tester, phone);
      expect(find.text('Remember on this browser'), findsNothing);
      expect(find.text('Sign out and remove data from this browser'),
          findsNothing);
    });

    testWidgets('remembering is off by default and says so', (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await show(tester, browser);
      await scrollTo(tester, 'Remember on this browser');
      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Remember on this browser'));
      expect(tile.value, isFalse);
      expect(
          find.text(
              'Off: your password is asked every time you open this page'),
          findsOneWidget);
      expect(kept.has(userId), isFalse);
    });

    testWidgets('turning it on warns, asks for the password, keeps the key',
        (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await show(tester, browser);
      await scrollTo(tester, 'Remember on this browser');
      await tester.tap(find.text('Remember on this browser'));
      await tester.pumpAndSettle();
      expect(find.text('Remember Zero-Trust Notes on this browser?'),
          findsOneWidget);
      expect(find.textContaining('shared or public computer'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remember'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Enter your password to remember Zero-Trust Notes on this browser.'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.tap(find.widgetWithText(FilledButton, 'Remember'));
      await settle(tester);

      expect(kept.has(userId), isTrue);
      expect(prefs.values['stay_unlocked'], 'true');
      expect(find.text('On: opens without your password on this browser'),
          findsOneWidget);
      expect(
          find.text('Never, remembered on this browser', skipOffstage: false),
          findsOneWidget);

      // Off again: the key is gone and the usual auto-lock is back.
      await tester.tap(find.text('Remember on this browser'));
      await settle(tester);
      expect(kept.has(userId), isFalse);
      expect(prefs.values['stay_unlocked'], 'false');
      expect(prefs.values['auto_lock'], '${notes.autoLockAfter!.inSeconds}');
      expect(
          find.text(
              'Off: your password is asked every time you open this page'),
          findsOneWidget);
    });

    testWidgets('cancelling the warning leaves it off', (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await show(tester, browser);
      await scrollTo(tester, 'Remember on this browser');
      await tester.tap(find.text('Remember on this browser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(kept.has(userId), isFalse);
      expect(prefs.values.containsKey('stay_unlocked'), isFalse);
    });

    testWidgets('a browser that cannot keep a key safely says so',
        (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      kept.available = false;
      await show(tester, browser);
      await scrollTo(tester, 'Remember on this browser');
      await tester.tap(find.text('Remember on this browser'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('secure (https) connection'), findsOneWidget);
      expect(kept.has(userId), isFalse);
    });

    testWidgets('the Auto-lock picker has no phone-only choice',
        (tester) async {
      await tester.runAsync(signedIn);
      await show(tester, browser);
      await scrollTo(tester, 'Auto-lock');
      await tester.tap(find.text('Auto-lock'));
      await settle(tester);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Never, even after closing the app'), findsNothing);
    });

    testWidgets('choosing a timed auto-lock turns remembering off',
        (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await tester.runAsync(() async {
        await account.rememberSession(Uint8List(32));
      });
      prefs.values['stay_unlocked'] = 'true';
      prefs.values['auto_lock'] = 'never';
      await show(tester, browser);
      await settle(tester);
      await scrollTo(tester, 'Auto-lock');
      await tester.tap(find.text('Auto-lock'));
      await settle(tester);
      await tester.tap(find.text('After 5 min'));
      await settle(tester);
      expect(kept.has(userId), isFalse);
      expect(prefs.values['stay_unlocked'], 'false');
    });

    testWidgets('sign out and remove data: confirms, signs out, wipes',
        (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await tester.runAsync(() async {
        await account.rememberSession(Uint8List(32));
      });
      await show(tester, browser);
      await scrollTo(tester, 'Sign out and remove data from this browser');
      expect(find.text('For shared or public computers'), findsOneWidget);
      await tester.tap(find.text('Sign out and remove data from this browser'));
      await tester.pumpAndSettle();
      expect(find.text('Remove your data from this browser?'), findsOneWidget);
      expect(find.textContaining("haven't synced yet will be lost"),
          findsOneWidget);

      // Cancel does nothing.
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(wipes, 0);
      expect(backend.currentUserId, userId);

      await tester.tap(find.text('Sign out and remove data from this browser'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Sign out and remove'));
      await settle(tester);
      expect(wipes, 1);
      expect(signedOut, 1);
      expect(backend.currentUserId, isNull);
      expect(kept.has(userId), isFalse);
    });

    testWidgets('the browser rows read right to left in Hebrew',
        (tester) async {
      await tester.runAsync(signedIn);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider.overrideWithValue(prefs),
          ztAppConfigProvider.overrideWithValue(notes),
          ztCapabilitiesProvider.overrideWithValue(browser),
        ],
        child: MaterialApp(
          locale: const Locale('he'),
          supportedLocales: ZtL10n.supportedLocales,
          localizationsDelegates: const [
            ZtL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ZtTheme.light(),
          home: ZtSettingsPage(onSignedOut: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'לזכור בדפדפן הזה');
      expect(find.text('כבוי: הסיסמה נדרשת בכל פתיחה של הדף'), findsOneWidget);
      // Right to left: the switch sits at the left edge, the text right of it.
      final text = tester.getCenter(find.text('לזכור בדפדפן הזה'));
      final toggle = tester.getCenter(find.descendant(
          of: find.widgetWithText(SwitchListTile, 'לזכור בדפדפן הזה'),
          matching: find.byType(Switch)));
      expect(toggle.dx, lessThan(text.dx));
    });
  });
}
