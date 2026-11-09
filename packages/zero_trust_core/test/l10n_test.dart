import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

void main() {
  Widget app(Locale locale) => ProviderScope(
        overrides: [
          accountServiceProvider
              .overrideWithValue(AccountService(FakeBackend(), params: fast)),
          ztPreferencesStoreProvider
              .overrideWithValue(InMemoryPreferencesStore()),
          ztAppConfigProvider.overrideWithValue(
            const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          // What an app adds: the core's strings next to Flutter's own.
          localizationsDelegates: const [
            ZtL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: ZtSignInScreen(onUnlocked: (_) {}),
        ),
      );

  testWidgets('core strings come from the delegate', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your Zero-Trust account.'), findsOneWidget);
    expect(ZtL10n.current.localeName, 'en');
  });

  testWidgets('a language the core lacks falls back to English',
      (tester) async {
    await tester.pumpWidget(app(const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your Zero-Trust account.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('messages without a BuildContext use the current language', () {
    expect(ztErrorMessage(const InvalidCredentials()),
        ZtL10n.current.errInvalidCredentials);
    expect(ZtL10n.current.syncedHoursAgo(1), 'Synced 1 hour ago');
    expect(ZtL10n.current.syncedHoursAgo(3), 'Synced 3 hours ago');
    expect(ZtL10n.current.itemsUnreadable(1), "1 item couldn't be read");
  });

  test('English is the template and the only built-in language for now', () {
    expect(ZtL10n.supportedLocales, [const Locale('en')]);
  });
}
