import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

const email = 'edo@example.com';
const password = 'correct horse battery';

/// Z10: every shared screen, in light and dark, passes Flutter's
/// accessibility guidelines (tap target size, labels on tappable things,
/// text contrast) and lays out without overflow at 200% text size.
void main() {
  late AccountService account;

  setUp(() async {
    account = AccountService(FakeBackend(),
        params: fast, biometrics: InMemoryBiometricKeyStore());
    await account.signUp(email: email, password: password);
  });

  final screens = <String, Widget Function()>{
    'sign-in': () =>
        ZtSignInScreen(onUnlocked: (_) {}, onForgotPassword: () {}),
    'unlock': () => ZtUnlockScreen(
        email: email,
        onUnlocked: (_) {},
        onSignOut: () {},
        onForgotPassword: () {},
        autoPromptBiometrics: false),
    'forgot password': () => const ZtForgotPasswordScreen(),
    'reset password': () => ZtResetPasswordScreen(onUnlocked: (_) {}),
    'recovery key': () =>
        ZtRecoveryKeyScreen(recoveryKey: RecoveryKey.generate(), onDone: () {}),
    'onboarding': () => ZtOnboardingScreen(onDone: () {}),
    'data protection': () => const ZtDataProtectionScreen(),
    'settings': () => ZtSettingsPage(
          onSignedOut: () {},
          version: '1.0.0',
          privacyPolicyUrl: Uri.parse('https://example.com/privacy'),
          termsUrl: Uri.parse('https://example.com/terms'),
          supportUrl: Uri.parse('https://example.com/support'),
          onOpenUrl: (_) {},
          onDataExported: (_, __) async {},
        ),
  };

  Widget app(Widget home, {required bool dark, double textScale = 1}) =>
      ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider
              .overrideWithValue(InMemoryPreferencesStore()),
          ztAppConfigProvider.overrideWithValue(
            const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'),
          ),
        ],
        child: MaterialApp(
          theme: ZtTheme.light(),
          darkTheme: ZtTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final dark in [false, true]) {
      testWidgets('$name (${dark ? 'dark' : 'light'}) meets the guidelines',
          (tester) async {
        final handle = tester.ensureSemantics();
        // A narrow phone, tall enough that long lists are fully built.
        tester.view.physicalSize = const Size(1080, 9000);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(build(), dark: dark));
        await settle(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('$name lays out at 200% text size', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340); // a common phone
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(build(), dark: false, textScale: 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'screen readers get headings, a spelled-out recovery key and '
      'the password hint', (tester) async {
    final handle = tester.ensureSemantics();
    await tester
        .pumpWidget(app(ZtSettingsPage(onSignedOut: () {}), dark: false));
    await settle(tester);
    expect(tester.getSemantics(find.text('Security')),
        matchesSemantics(label: 'Security', isHeader: true));

    final key = RecoveryKey.generate();
    await tester.pumpWidget(
        app(ZtRecoveryKeyScreen(recoveryKey: key, onDone: () {}), dark: false));
    await settle(tester);
    final text = await tester.runAsync(key.format);
    final first = text!.split('-')[1];
    expect(
        find.bySemanticsLabel(
            RegExp('^Recovery key: Z T, ${first.split('').join(' ')}, ')),
        findsOneWidget);

    await tester
        .pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {}), dark: false));
    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'aaaaaaaaaaaa');
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp(r'^Password strength: [^.]+\. .+')),
        findsOneWidget);
    handle.dispose();
  });
}
