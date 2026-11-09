import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

const email = 'edo@example.com';
const password = 'correct horse battery';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late FakeBackend backend;
  late AccountService account;
  late InMemoryPreferencesStore prefs;

  setUp(() {
    backend = FakeBackend();
    account = AccountService(backend, params: fast, legacyParams: fast);
    prefs = InMemoryPreferencesStore();
  });

  Widget app(Widget home, {List<Locale>? locales}) => ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider.overrideWithValue(prefs),
          ztAppConfigProvider.overrideWithValue(
            const ZtAppConfig(
                appId: 'fitness', displayName: 'Zero-Trust Fitness'),
          ),
        ],
        child: MaterialApp(theme: ZtTheme.light(), home: home),
      );

  /// [andSettle] false while a spinner keeps animating.
  Future<void> settle(WidgetTester tester, {bool andSettle = true}) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    if (andSettle) await tester.pumpAndSettle();
  }

  group('onboarding (Z12)', () {
    testWidgets('three pages, then remembered', (tester) async {
      var done = 0;
      await tester.pumpWidget(app(ZtOnboardingScreen(onDone: () => done++)));
      await tester.pumpAndSettle();

      expect(find.text('Only you can read your data'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Keep your recovery key safe'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock with a touch'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      expect(done, 1);
      expect(prefs.values['onboarding_seen'], 'true');
    });

    testWidgets('skip marks it seen', (tester) async {
      var done = false;
      await tester.pumpWidget(app(ZtOnboardingScreen(onDone: () => done = true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(done, isTrue);
      expect(prefs.values['onboarding_seen'], 'true');
    });

    test('seen provider loads the stored answer', () async {
      prefs.values['onboarding_seen'] = 'true';
      final container = ProviderContainer(overrides: [
        ztPreferencesStoreProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);
      expect(container.read(ztOnboardingSeenProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(ztOnboardingSeenProvider), isTrue);

      final fresh = ProviderContainer(overrides: [
        ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
      ]);
      addTearDown(fresh.dispose);
      fresh.read(ztOnboardingSeenProvider);
      await Future<void>.delayed(Duration.zero);
      expect(fresh.read(ztOnboardingSeenProvider), isFalse);
    });

    Future<void> signIn(WidgetTester tester, InMemoryBiometricKeyStore bio,
        {required bool turnOn}) async {
      account = AccountService(backend, params: fast, biometrics: bio);
      await account.signUp(email: email, password: password);
      UnlockResult? result;
      await tester.pumpWidget(app(ZtSignInScreen(
          offerBiometrics: true, onUnlocked: (r) => result = r)));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), email);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      // The sign-in button spins behind the dialog.
      await settle(tester, andSettle: false);

      expect(find.text('Unlock with biometrics?'), findsOneWidget);
      expect(result, isNull, reason: 'waits for the answer');
      await tester.tap(find.text(turnOn ? 'Turn on' : 'Not now'));
      await settle(tester);
      expect(result, isNotNull);
    }

    testWidgets('sign-in offers biometrics and turns them on', (tester) async {
      final bio = InMemoryBiometricKeyStore();
      await signIn(tester, bio, turnOn: true);
      expect(await bio.isEnabled(email), isTrue);
    });

    testWidgets('"Not now" leaves biometrics off', (tester) async {
      final bio = InMemoryBiometricKeyStore();
      await signIn(tester, bio, turnOn: false);
      expect(await bio.isEnabled(email), isFalse);
    });

    testWidgets('no offer without hardware', (tester) async {
      account = AccountService(backend,
          params: fast,
          biometrics: InMemoryBiometricKeyStore(available: false));
      await account.signUp(email: email, password: password);
      var unlocked = false;
      await tester.pumpWidget(app(ZtSignInScreen(
          offerBiometrics: true, onUnlocked: (_) => unlocked = true)));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), email);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.text('Unlock with biometrics?'), findsNothing);
      expect(unlocked, isTrue);
    });
  });

  group('settings links (Z5)', () {
    testWidgets('help, privacy, terms and licences', (tester) async {
      await account.signUp(email: email, password: password);
      final opened = <Uri>[];
      final support = Uri.parse('mailto:support@example.com');
      final privacy = Uri.parse('https://example.com/privacy');
      final terms = Uri.parse('https://example.com/terms');
      await tester.pumpWidget(app(ZtSettingsPage(
        onSignedOut: () {},
        version: '1.2.3',
        supportUrl: support,
        privacyPolicyUrl: privacy,
        termsUrl: terms,
        onOpenUrl: opened.add,
      )));
      await settle(tester);

      for (final label in ['Help and feedback', 'Privacy policy', 'Terms of use']) {
        await tester.scrollUntilVisible(find.text(label), 100);
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(opened, [support, privacy, terms]);

      await tester.scrollUntilVisible(find.text('Open-source licences'), 100);
      await tester.tap(find.text('Open-source licences'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('links hidden without URLs; licences always there',
        (tester) async {
      await account.signUp(email: email, password: password);
      await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
      await settle(tester);
      expect(find.text('Terms of use'), findsNothing);
      expect(find.text('Help and feedback'), findsNothing);
      await tester.scrollUntilVisible(find.text('Open-source licences'), 100);
      expect(find.text('Open-source licences'), findsOneWidget);
    });
  });
}
