import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

/// Z22: deleting waits 7 days, and every app offers to keep the account.
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

  testWidgets('deleting from settings schedules it and says until when',
      (tester) async {
    await account.signUp(email: email, password: password);
    var signedOut = 0;
    await tester
        .pumpWidget(app(ZtSettingsPage(onSignedOut: () => signedOut++)));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Delete account'), 100);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('after 7 days'), findsOneWidget);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Account deletion scheduled'), findsOneWidget);
    expect(find.textContaining('November 29, 2026'), findsOneWidget);
    expectOnScreen(tester, find.widgetWithText(TextButton, 'OK'));
    expect(signedOut, 0, reason: 'waits for the person to read it');
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await settle(tester);
    expect(signedOut, 1);
    expect(backend.profiles, contains(email), reason: 'nothing deleted yet');
    expect(backend.scheduled, contains(email));
  });

  testWidgets('after unlock, the app offers to keep the account',
      (tester) async {
    await account.signUp(email: email, password: password);
    backend.scheduled[email] = DateTime.utc(2026, 11, 29, 12);
    UnlockResult? result;
    await tester.pumpWidget(
        app(ZtUnlockScreen(email: email, onUnlocked: (r) => result = r)));
    await settle(tester);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);

    expect(result, isNotNull, reason: 'the app opens right away');
    expect(find.text('Your account is set to be deleted'), findsOneWidget);
    final keep = find.widgetWithText(TextButton, 'Keep my account');
    expectOnScreen(tester, keep);
    expectOnScreen(
        tester, find.widgetWithText(TextButton, 'Delete as planned'));
    await tester.tap(keep);
    await settle(tester);
    expect(backend.scheduled, isEmpty);
    expect(find.text("Your account won't be deleted."), findsOneWidget);
  });

  testWidgets('"Delete as planned" leaves it scheduled', (tester) async {
    await account.signUp(email: email, password: password);
    backend.scheduled[email] = DateTime.utc(2026, 11, 29, 12);
    await tester
        .pumpWidget(app(ZtUnlockScreen(email: email, onUnlocked: (_) {})));
    await settle(tester);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete as planned'));
    await settle(tester);
    expect(backend.scheduled, contains(email));
  });

  testWidgets('no dialog for an account that is not being deleted',
      (tester) async {
    await account.signUp(email: email, password: password);
    await tester
        .pumpWidget(app(ZtUnlockScreen(email: email, onUnlocked: (_) {})));
    await settle(tester);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('settings show the date and keep it, Hebrew right to left',
      (tester) async {
    await account.signUp(email: email, password: password);
    backend.scheduled[email] = DateTime.utc(2026, 11, 29, 12);
    await tester.pumpWidget(
        app(ZtSettingsPage(onSignedOut: () {}), locale: const Locale('he')));
    await settle(tester);

    final tile = find.text('החשבון שלך מתוזמן למחיקה');
    expect(tile, findsOneWidget);
    expectOnScreen(tester, tile);
    // Right to left: the icon sits right of the title.
    final icon = find.descendant(
        of: find.ancestor(of: tile, matching: find.byType(ListTile)),
        matching: find.byIcon(Icons.delete_forever_outlined));
    expect(tester.getCenter(icon).dx, greaterThan(tester.getCenter(tile).dx));

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'השארת החשבון'));
    await settle(tester);
    expect(backend.scheduled, isEmpty);
    expect(tile, findsNothing);
  });
}
