import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

const email = 'edo@example.com';
const password = 'correct horse battery';
const notes = ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes');

/// "Never, even after closing the app": an opt-in Auto-lock choice that
/// keeps the key on the phone so the app opens without asking. Every other
/// choice, and the default, must behave exactly as before.
void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late FakeBackend backend;
  late InMemorySessionKeyStore kept;
  late AccountService account;
  late InMemoryPreferencesStore prefs;

  setUp(() {
    backend = FakeBackend();
    kept = InMemorySessionKeyStore();
    account = AccountService(backend,
        params: fast, legacyParams: fast, sessionKeys: kept);
    prefs = InMemoryPreferencesStore();
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      accountServiceProvider.overrideWithValue(account),
      ztPreferencesStoreProvider.overrideWithValue(prefs),
      ztAppConfigProvider.overrideWithValue(notes),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Widget app(Widget home) => ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztPreferencesStoreProvider.overrideWithValue(prefs),
          ztAppConfigProvider.overrideWithValue(notes),
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

  Future<String> signedIn() async {
    await account.signUp(email: email, password: password);
    return backend.currentUserId!;
  }

  group('account service', () {
    test('remembers, resumes and forgets the key', () async {
      final userId = await signedIn();
      final dek = Uint8List.fromList(List.filled(32, 7));
      await account.rememberSession(dek, legacyDek: true);
      expect(dek.every((b) => b == 7), isTrue, reason: 'caller keeps its key');

      final resumed = await account.resumeSession();
      expect(resumed!.dek, List.filled(32, 7));
      expect(resumed.legacyDek, isTrue);

      await account.forgetSession();
      expect(kept.has(userId), isFalse);
      expect(await account.resumeSession(), isNull);
    });

    test('a save still in flight cannot bring back a forgotten key', () async {
      final slow = _SlowSessionKeyStore();
      account = AccountService(backend,
          params: fast, legacyParams: fast, sessionKeys: slow);
      final userId = await signedIn();

      // Lock now while the save is waiting on the key store.
      final saving = account.rememberSession(Uint8List(32));
      await pumpEventQueue();
      expect(slow.waiting, isTrue);
      final forgetting = account.forgetSession();
      slow.release();
      await Future.wait([saving, forgetting]);
      expect(slow.has(userId), isFalse);
      expect(await account.resumeSession(), isNull);

      // Lock now before the save has even started.
      final early = account.rememberSession(Uint8List(32));
      await account.forgetSession();
      slow.release();
      await early;
      expect(slow.has(userId), isFalse);

      // A save asked for after the lock is kept as usual.
      final later = account.rememberSession(Uint8List(32));
      await pumpEventQueue();
      slow.release();
      await later;
      expect(slow.has(userId), isTrue);
    });

    test('a phone without a screen lock neither keeps nor resumes', () async {
      final userId = await signedIn();
      kept.available = false;
      expect(await account.stayUnlockedAvailable(), isFalse);
      await account.rememberSession(Uint8List(32));
      expect(kept.has(userId), isFalse);

      // Kept earlier, then the screen lock was removed: asks again.
      kept.available = true;
      await account.rememberSession(Uint8List(32));
      kept.available = false;
      expect(await account.resumeSession(), isNull);
      expect(kept.has(userId), isFalse);
    });

    test('sign-out and account deletion remove the kept key', () async {
      final userId = await signedIn();
      await account.rememberSession(Uint8List(32));
      await account.signOut();
      expect(kept.has(userId), isFalse);

      await account.signIn(email: email, password: password);
      await account.rememberSession(Uint8List(32));
      await account.deleteAccount(password: password);
      expect(kept.has(userId), isFalse);
    });
  });

  group('vault', () {
    test('with the default choice nothing is kept (unchanged behaviour)',
        () async {
      final userId = await signedIn();
      final c = container();
      expect(c.read(ztStayUnlockedProvider), isFalse);
      await c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
      await pumpEventQueue();
      expect(kept.has(userId), isFalse);
      expect(c.read(ztAutoLockProvider), notes.autoLockAfter);
    });

    test('when on, each unlock keeps the key and Lock now removes it',
        () async {
      final userId = await signedIn();
      final c = container();
      await c.read(ztStayUnlockedProvider.notifier).set(true);
      final dek = Uint8List.fromList(List.filled(32, 3));
      await c.read(vaultControllerProvider.notifier).unlock(dek);
      await pumpEventQueue();
      expect(dek.every((b) => b == 0), isTrue, reason: 'DEK still zeroed');
      expect(kept.has(userId), isTrue);
      expect((await account.resumeSession())!.dek, List.filled(32, 3));

      c.read(vaultControllerProvider.notifier).lock();
      // Even straight away, the unlock screen must not reopen the vault.
      expect(await account.resumeSession(), isNull);
      expect(kept.has(userId), isFalse);
    });

    test('the choice is remembered for the next launch', () async {
      await container().read(ztStayUnlockedProvider.notifier).set(true);
      expect(prefs.values['stay_unlocked'], 'true');
      expect(await container().read(ztStayUnlockedProvider.notifier).current(),
          isTrue);
    });
  });

  group('unlock screen', () {
    testWidgets('opens on its own with a kept key', (tester) async {
      await tester.runAsync(signedIn);
      await account.rememberSession(Uint8List.fromList(List.filled(32, 5)));
      UnlockResult? result;
      await tester.pumpWidget(
          app(ZtUnlockScreen(email: email, onUnlocked: (r) => result = r)));
      await tester.pumpAndSettle();
      expect(result!.dek, List.filled(32, 5));
    });

    testWidgets('without one, asks as before with the password focused',
        (tester) async {
      await tester.runAsync(signedIn);
      UnlockResult? result;
      await tester.pumpWidget(
          app(ZtUnlockScreen(email: email, onUnlocked: (r) => result = r)));
      await tester.pumpAndSettle();
      expect(result, isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await settle(tester);
      expect(result, isNotNull);
    });
  });

  group('settings', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto-lock'));
      await settle(tester);
    }

    testWidgets('the new choice sits last, under "Never"', (tester) async {
      await tester.runAsync(signedIn);
      await openPicker(tester);
      final never = tester.getTopLeft(find.text('Never'));
      final stay =
          tester.getTopLeft(find.text('Never, even after closing the app'));
      expect(stay.dy, greaterThan(never.dy));
      expect(stay.dx, never.dx);
      // The existing choices are all still there.
      for (final label in [
        'Immediately',
        'After 1 min',
        'After 5 min',
        'After 15 min',
      ]) {
        expect(tester.getTopLeft(find.text(label)).dy, lessThan(never.dy));
      }
    });

    testWidgets(
        'turning it on explains, asks for the password and keeps the key',
        (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await openPicker(tester);
      await tester.tap(find.text('Never, even after closing the app'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anyone who can unlock your phone'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Keep open'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your password to keep Zero-Trust Notes open.'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.tap(find.widgetWithText(FilledButton, 'Keep open'));
      await settle(tester);

      expect(kept.has(userId), isTrue);
      expect(prefs.values['stay_unlocked'], 'true');
      expect(prefs.values['auto_lock'], 'never');
      expect(find.text('Never, stays open even after closing'), findsOneWidget);

      // Any other choice turns it off and removes the key.
      await tester.tap(find.text('Auto-lock'));
      await settle(tester);
      await tester.tap(find.text('After 5 min'));
      await settle(tester);
      expect(kept.has(userId), isFalse);
      expect(prefs.values['stay_unlocked'], 'false');
      expect(prefs.values['auto_lock'], '300');
    });

    testWidgets('a wrong password or cancel leaves it off', (tester) async {
      final userId = (await tester.runAsync(signedIn))!;
      await openPicker(tester);
      await tester.tap(find.text('Never, even after closing the app'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Keep open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'not the password');
      await tester.tap(find.widgetWithText(FilledButton, 'Keep open'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'still asking');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(kept.has(userId), isFalse);
      expect(prefs.values.containsKey('stay_unlocked'), isFalse);
      expect(prefs.values.containsKey('auto_lock'), isFalse);
    });

    testWidgets('without a screen lock the choice is shown but off',
        (tester) async {
      await tester.runAsync(signedIn);
      kept.available = false;
      await openPicker(tester);
      expect(find.text('Needs a screen lock on your phone'), findsOneWidget);
      final tile = tester.widget<RadioListTile<(Duration?, bool)>>(
          find.ancestor(
              of: find.text('Never, even after closing the app'),
              matching: find.byType(RadioListTile<(Duration?, bool)>)));
      expect(tile.enabled, isFalse);
    });
  });
}

/// Holds each availability check until [release], to put a save in flight.
class _SlowSessionKeyStore extends InMemorySessionKeyStore {
  Completer<void>? _gate;

  bool get waiting => _gate != null;

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<bool> isAvailable() async {
    final gate = _gate = Completer<void>();
    await gate.future;
    return available;
  }
}
