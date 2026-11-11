import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

void main() {
  late InMemoryPreferencesStore prefs;
  late AccountService account;

  setUp(() {
    prefs = InMemoryPreferencesStore();
    account = AccountService(FakeBackend(), params: fast);
    ZtLanguageController.resetPreload();
  });

  List<Override> overrides() => [
        accountServiceProvider.overrideWithValue(account),
        ztPreferencesStoreProvider.overrideWithValue(prefs),
        ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'),
        ),
      ];

  Widget app(Locale locale, [Widget? home]) => ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          locale: locale,
          // What an app adds: the core's strings next to Flutter's own.
          localizationsDelegates: const [
            ZtL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('he'), Locale('de')],
          home: home ?? ZtSignInScreen(onUnlocked: (_) {}),
        ),
      );

  /// An app wired the recommended way: language from [ztLanguageProvider].
  Widget wiredApp(Widget home) => ProviderScope(
        overrides: overrides(),
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(ztLanguageProvider),
            supportedLocales: ZtLanguages.supported,
            localizationsDelegates: ZtLanguages.delegates,
            home: home,
          ),
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

  testWidgets('Hebrew: core screens are translated and right-to-left',
      (tester) async {
    await tester.pumpWidget(app(const Locale('he')));
    await tester.pumpAndSettle();
    expect(find.text('התחברות עם חשבון Zero-Trust.'), findsOneWidget);
    expect(ZtL10n.current.localeName, 'he');
    expect(Intl.defaultLocale, 'he');

    final context = tester.element(find.byType(ZtSignInScreen));
    expect(Directionality.of(context), TextDirection.rtl);

    // The email field's label sits on the right, but the address itself
    // is typed left-to-right.
    final emailField = find.widgetWithText(TextFormField, 'אימייל');
    final label = tester.getRect(find.text('אימייל'));
    final field = tester.getRect(emailField);
    expect(label.right, greaterThan(field.center.dx));
    final editable = tester.widget<EditableText>(
        find.descendant(of: emailField, matching: find.byType(EditableText)));
    expect(editable.textDirection, TextDirection.ltr);

    // Back to English: dates format in English again.
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(Intl.defaultLocale, 'en');
  });

  test('messages without a BuildContext use the current language', () {
    ZtL10n.current = lookupZtLocalizations(const Locale('en'));
    expect(ztErrorMessage(const InvalidCredentials()),
        ZtL10n.current.errInvalidCredentials);
    expect(ZtL10n.current.syncedHoursAgo(1), 'Synced 1 hour ago');
    expect(ZtL10n.current.syncedHoursAgo(3), 'Synced 3 hours ago');
    expect(ZtL10n.current.itemsUnreadable(1), "1 item couldn't be read");

    final he = lookupZtLocalizations(const Locale('he'));
    expect(he.syncedHoursAgo(1), 'סונכרן לפני שעה');
    expect(he.syncedHoursAgo(2), 'סונכרן לפני שעתיים');
    expect(he.syncedHoursAgo(5), 'סונכרן לפני 5 שעות');
  });

  test('the core ships English and Hebrew', () {
    expect(ZtL10n.supportedLocales.map((l) => l.languageCode).toSet(),
        {'en', 'he'});
    expect(ZtLanguages.supported.first, ZtLanguages.english);
  });

  test(
      'every English string has a Hebrew translation with the same '
      'placeholders', () {
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('lib/l10n/$name').readAsStringSync())
            as Map<String, dynamic>;
    final en = read('zt_en.arb');
    final he = read('zt_he.arb');
    final keys = en.keys.where((k) => !k.startsWith('@'));
    final placeholder = RegExp(r'\{(\w+)[,}]');
    for (final key in keys) {
      expect(he[key], isA<String>(), reason: 'zt_he.arb is missing "$key"');
      final want =
          placeholder.allMatches(en[key] as String).map((m) => m[1]).toSet();
      final got =
          placeholder.allMatches(he[key] as String).map((m) => m[1]).toSet();
      expect(got, want, reason: 'placeholders differ in "$key"');
    }
  });

  group('language setting', () {
    test('English until the user picks another', () async {
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      expect(container.read(ztLanguageProvider), ZtLanguages.english);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(ztLanguageProvider), ZtLanguages.english);
    });

    test('a stored choice is loaded, and null follows the phone', () async {
      prefs.values['language'] = 'he';
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      container.read(ztLanguageProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(ztLanguageProvider), ZtLanguages.hebrew);

      await container.read(ztLanguageProvider.notifier).set(null);
      expect(container.read(ztLanguageProvider), isNull);
      expect(prefs.values['language'], 'phone');
    });

    test('preload makes the first frame use the stored language', () async {
      prefs.values['language'] = 'he';
      await ZtLanguageController.preload(prefs);
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      expect(container.read(ztLanguageProvider), ZtLanguages.hebrew);
    });

    testWidgets('Settings → Language switches the whole app to Hebrew',
        (tester) async {
      await account.signUp(email: 'a@b.co', password: 'correct horse battery');
      await tester.pumpWidget(wiredApp(ZtSettingsPage(onSignedOut: () {})));
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(ListTile, 'Language');
      await tester.scrollUntilVisible(tile, 100);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(find.descendant(of: tile, matching: find.text('English')),
          findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('עברית'));
      await tester.pumpAndSettle();

      expect(prefs.values['language'], 'he');
      expect(find.text('הגדרות'), findsOneWidget); // App bar: "Settings".
      final context = tester.element(find.byType(ZtSettingsPage));
      expect(Directionality.of(context), TextDirection.rtl);

      // Right-to-left for real: the row's icon is now on the right.
      final heTile = find.widgetWithText(ListTile, 'שפה');
      await tester.ensureVisible(heTile);
      await tester.pumpAndSettle();
      final icon = tester.getRect(
          find.descendant(of: heTile, matching: find.byIcon(Icons.language)));
      final title = tester
          .getRect(find.descendant(of: heTile, matching: find.text('שפה')));
      expect(icon.left, greaterThan(title.right));

      // And back.
      await tester.tap(heTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(prefs.values['language'], 'en');
    });
  });
}
