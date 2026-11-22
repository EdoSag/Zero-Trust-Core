import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

/// Z14: change the account's email from settings.
void main() {
  late GraceFakeBackend backend;
  late AccountService account;
  const email = 'edo@example.com';
  const password = 'correct horse battery';

  setUp(() {
    backend = GraceFakeBackend();
    account = AccountService(backend, params: fast, legacyParams: fast);
  });

  Widget app(Widget home, {Locale? locale}) => ProviderScope(
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
          locale: locale,
          localizationsDelegates: ZtLanguages.delegates,
          supportedLocales: ZtL10n.supportedLocales,
          home: home,
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

  void expectOnScreen(WidgetTester tester, Finder finder) {
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(finder);
    expect(rect.width, greaterThan(0));
    expect(
        screen.contains(rect.topLeft) &&
            screen.contains(rect.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: '$finder at $rect is off screen');
  }

  testWidgets('change email from settings, step by step', (tester) async {
    await account.signUp(email: email, password: password);
    await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
    await settle(tester);

    final tile = find.text('Change email');
    expectOnScreen(tester, tile);
    // Under "Change password", same column.
    expect(tester.getRect(tile).top,
        greaterThan(tester.getRect(find.text('Change password')).bottom));
    await tester.tap(tile);
    await settle(tester);

    await tester.enterText(
        find.byKey(const Key('zt-new-email')), 'new@example.com');
    await tester.enterText(
        find.byKey(const Key('zt-current-password')), password);
    final send = find.widgetWithText(FilledButton, 'Send code');
    expectOnScreen(tester, send);
    await tester.tap(send);
    await settle(tester);
    expect(backend.codesSent, hasLength(1));
    expect(find.text('Enter the 6-digit code we sent to new@example.com.'),
        findsOneWidget);

    await tester.enterText(find.byKey(const Key('zt-email-code')), '999999');
    await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
    await settle(tester);
    expect(find.textContaining("That code isn't right"), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('zt-email-code')), backend.codesSent.single);
    await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
    await settle(tester);
    expect(find.byType(ZtChangeEmailScreen), findsNothing);
    expect(find.text('Your account now signs in with new@example.com.'),
        findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget,
        reason: 'the account row shows the new address');
  });

  testWidgets('wrong password: no code, a clear message', (tester) async {
    await account.signUp(email: email, password: password);
    await tester.pumpWidget(app(const ZtChangeEmailScreen()));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('zt-new-email')), 'new@example.com');
    await tester.enterText(
        find.byKey(const Key('zt-current-password')), 'not my password');
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await settle(tester);
    expect(backend.codesSent, isEmpty);
    expect(find.byKey(const Key('zt-email-code')), findsNothing);
  });

  testWidgets('Hebrew: right to left, the address stays left to right',
      (tester) async {
    await account.signUp(email: email, password: password);
    await tester.pumpWidget(
        app(const ZtChangeEmailScreen(), locale: const Locale('he')));
    await settle(tester);
    expect(find.text('שינוי כתובת המייל'), findsOneWidget);
    final field = find.byKey(const Key('zt-new-email'));
    final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.textDirection, TextDirection.ltr);
    final button = find.widgetWithText(FilledButton, 'שליחת קוד');
    expectOnScreen(tester, button);
    expect(tester.getRect(button).width, greaterThan(200));
  });

  test('backends without it hide the setting', () {
    final plain = AccountService(FakeBackend(), params: fast);
    expect(plain.canChangeEmail, isFalse);
    expect(account.canChangeEmail, isTrue);
  });
}
