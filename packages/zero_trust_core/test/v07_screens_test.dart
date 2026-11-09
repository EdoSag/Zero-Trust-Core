import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

const email = 'edo@example.com';
const strong = 'ocean-maple-rocket-violin';

/// Says every password is breached, and counts calls.
class AlwaysBreached implements BreachedPasswordChecker {
  int calls = 0;
  @override
  Future<int> timesSeen(String password) async {
    calls++;
    return 42;
  }
}

/// Holds the check open until [release], to edit the form meanwhile.
class SlowCheck implements BreachedPasswordChecker {
  final gate = Completer<void>();
  final checked = <String>[];
  @override
  Future<int> timesSeen(String password) async {
    checked.add(password);
    await gate.future;
    return 0;
  }
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late FakeBackend backend;
  late AccountService account;
  late InMemoryPreferencesStore prefs;
  late BreachedPasswordChecker breaches;

  setUp(() {
    backend = FakeBackend();
    account = AccountService(backend, params: fast, legacyParams: fast);
    prefs = InMemoryPreferencesStore();
    breaches = const NoBreachCheck();
  });

  Widget app(Widget home) => ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider.overrideWithValue(prefs),
          ztBreachedPasswordCheckerProvider.overrideWith((_) => breaches),
          ztAppConfigProvider.overrideWithValue(
            const ZtAppConfig(appId: 'tasks', displayName: 'Zero-Trust Tasks'),
          ),
        ],
        child: MaterialApp(theme: ZtTheme.light(), home: home),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> fillSignUp(WidgetTester tester, String password) async {
    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'), password);
    await tester.pump();
  }

  testWidgets('sign-up shows strength and refuses a weak password',
      (tester) async {
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {})));
    await fillSignUp(tester, 'Summer2024!!');
    expect(find.textContaining('Weak'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.textContaining('Too easy to guess'), findsOneWidget);
    expect(backend.profiles, isEmpty);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), strong);
    await tester.pump();
    expect(find.textContaining('Strong'), findsOneWidget);
  });

  testWidgets('sign-up refuses a breached password before reaching the server',
      (tester) async {
    final checker = AlwaysBreached();
    breaches = checker;
    UnlockResult? result;
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (r) => result = r)));
    await fillSignUp(tester, strong);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    expect(checker.calls, 1);
    expect(find.textContaining('appeared in data breaches'), findsOneWidget);
    expect(result, isNull);
    expect(backend.profiles, isEmpty);
  });

  testWidgets('sign-up uses the password that was checked, not a later edit',
      (tester) async {
    final slow = SlowCheck();
    breaches = slow;
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {})));
    await fillSignUp(tester, strong);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'x');
    slow.gate.complete();
    await settle(tester);
    expect(slow.checked, [strong]);
    await tester.runAsync(() async {
      await account.signOut();
      await account.signIn(email: email, password: strong);
    });
  });

  testWidgets(
      'pre-core accounts sign in with old, weak or breached passwords and '
      'keep their data key', (tester) async {
    // A Tasks/Fitness/Contacts account from before the core: Supabase
    // password = the raw password, data key = PBKDF2(password, salt).
    const old = 'summer2024';
    final checker = AlwaysBreached();
    breaches = checker;
    final legacySalt = Kdf.newSalt();
    final todaysKey = await tester.runAsync(() =>
        Kdf.deriveMasterKey(password: old, salt: legacySalt, params: fast));
    backend.authPasswords[email] = old;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));

    UnlockResult? result;
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (r) => result = r)));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), old);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    expect(result, isNotNull);
    expect(result!.legacyDek, isTrue);
    expect(result!.dek, todaysKey, reason: 'old data stays readable');
    expect(checker.calls, 0, reason: 'signing in is never checked');
  });

  testWidgets('settings: data protection screen, other apps, wallpaper colours',
      (tester) async {
    await account.signUp(email: email, password: strong);
    final opened = <Uri>[];
    await tester.pumpWidget(app(ZtSettingsPage(
      onSignedOut: () {},
      onOpenUrl: opened.add,
    )));

    await tester.scrollUntilVisible(
        find.text('How your data is protected'), 100);
    await tester.tap(find.text('How your data is protected'));
    await tester.pumpAndSettle();
    expect(find.text('Encrypted on your phone'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Other Zero-Trust apps'), 100);
    expect(find.text('Zero-Trust Tasks'), findsOneWidget,
        reason: 'only in About: the current app is not listed');
    for (final name in ['Notes', 'Fitness', 'Contacts']) {
      await tester.scrollUntilVisible(find.text('Zero-Trust $name'), 100);
    }
    await tester.tap(find.text('Zero-Trust Contacts'));
    expect(opened.single.toString(),
        'https://play.google.com/store/apps/details?id=dev.sagron.zerotrustcontacts');

    // No wallpaper palette in tests (as on iOS): the switch is hidden.
    expect(find.text('Use wallpaper colours'), findsNothing);
  });

  testWidgets('settings: change password checks strength and breaches',
      (tester) async {
    await account.signUp(email: email, password: strong);
    final checker = AlwaysBreached();
    breaches = checker;
    await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'), strong);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'password1234');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'password1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pump();
    expect(find.textContaining('Too easy to guess'), findsOneWidget);
    expect(checker.calls, 0);

    const next = 'violin-rocket-maple-ocean';
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), next);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'), next);
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await settle(tester);
    expect(find.textContaining('appeared in data breaches'), findsOneWidget);
    expect(checker.calls, 1);
  });

  testWidgets('theme choice is remembered across launches', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(app(Consumer(builder: (_, r, __) {
      ref = r;
      return const SizedBox();
    })));
    await ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await ref.read(ztDynamicColorProvider.notifier).set(true);
    expect(prefs.values['theme_mode'], 'dark');

    // A new launch reads it back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(Consumer(builder: (_, r, __) {
      ref = r;
      r.watch(themeModeProvider);
      r.watch(ztDynamicColorProvider);
      return const SizedBox();
    })));
    await tester.pump();
    expect(ref.read(themeModeProvider), ThemeMode.dark);
    expect(ref.read(ztDynamicColorProvider), isTrue);
  });

  testWidgets('ZtThemeBuilder gives the app its suite accent', (tester) async {
    ThemeData? light;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ztPreferencesStoreProvider.overrideWithValue(prefs),
        ztAppConfigProvider.overrideWithValue(const ZtAppConfig(
            appId: 'fitness', displayName: 'Zero-Trust Fitness')),
      ],
      child: ZtThemeBuilder(builder: (_, theme, dark, mode) {
        light = theme;
        return MaterialApp(
            theme: theme,
            darkTheme: dark,
            themeMode: mode,
            home: const SizedBox());
      }),
    ));
    expect(light!.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: ZtTheme.brandSeed).primary);
    expect(light!.colorScheme.secondary,
        ColorScheme.fromSeed(seedColor: ZtSuite.fitness.accent).primary);
  });

  group('error messages', () {
    test('sync and storage errors say what to do', () {
      expect(ztErrorMessage(const ItemFromNewerVersion('a', 3)),
          contains('Update the app'));
      expect(ztErrorMessage(const AttachmentTooLarge(30000000, 20000000)),
          contains('20 MB'));
      expect(ztErrorMessage(const AttachmentCorrupt('x')),
          contains('wasn\'t opened'));
      expect(ztErrorMessage(Exception('SocketException: Failed host lookup')),
          contains('offline'));
      expect(ztErrorMessage(const VaultIsLocked()), 'Unlock the app first.');
    });
  });

  group('whileShowingSystemUi', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    void away() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }

    void back() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    ProviderContainer container() => ProviderContainer(overrides: [
          ztAppConfigProvider.overrideWithValue(const ZtAppConfig(
              appId: 'contacts',
              displayName: 'Zero-Trust Contacts',
              autoLockAfter: Duration.zero)),
          ztPreferencesStoreProvider
              .overrideWithValue(InMemoryPreferencesStore()),
        ]);

    test('"Immediately" does not lock while a picker is open', () {
      fakeAsync((async) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        final c = container();
        final vault = c.read(vaultControllerProvider.notifier);
        vault.unlock(Uint8List(32));
        async.flushMicrotasks();

        var picked = false;
        vault.whileShowingSystemUi(() async {
          away(); // the system picker covers the app
          await Future<void>.delayed(const Duration(minutes: 2));
          back();
          picked = true;
        });
        async.elapse(const Duration(minutes: 3));
        expect(picked, isTrue);
        expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());

        // Afterwards the usual rule applies again.
        away();
        expect(c.read(vaultControllerProvider), isA<VaultLocked>());
        c.dispose();
      });
    });

    test('a picker left open past the grace period still locks', () {
      fakeAsync((async) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        final c = container();
        final vault = c.read(vaultControllerProvider.notifier);
        vault.unlock(Uint8List(32));
        async.flushMicrotasks();
        vault.whileShowingSystemUi(() async {
          away();
          await Future<void>.delayed(const Duration(minutes: 16));
        });
        async.elapse(const Duration(minutes: 16));
        back();
        expect(c.read(vaultControllerProvider), isA<VaultLocked>());
        c.dispose();
      });
    });
  });
}
