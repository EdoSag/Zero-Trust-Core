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

  setUp(() {
    backend = FakeBackend();
    account = AccountService(backend, params: fast, legacyParams: fast);
  });

  Widget app(Widget home) => ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          ztAppConfigProvider.overrideWithValue(
            const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'),
          ),
        ],
        child: MaterialApp(theme: ZtTheme.light(), home: home),
      );

  /// The crypto runs on real timers; let it finish, then rebuild.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'create account returns a recovery key; the server never sees the password',
      (tester) async {
    UnlockResult? result;
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (r) => result = r)));

    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);

    expect(result, isNotNull);
    expect(result!.newRecoveryKey, isNotNull);
    expect(backend.passwordsSeenByServer, isNot(contains(password)));
  });

  testWidgets('sign-in validates input and explains wrong credentials',
      (tester) async {
    await account.signUp(email: email, password: password);
    await account.signOut();
    UnlockResult? result;
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (r) => result = r)));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'wrong password!!');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    expect(find.text('That email and password don\'t match.'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    expect(result, isNotNull);
    expect(result!.newRecoveryKey, isNull);
  });

  testWidgets('pre-core accounts with short passwords can still sign in',
      (tester) async {
    await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {})));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    expect(find.text('Use at least 12 characters.'), findsNothing);
    // It reached the server, which rejected the unknown account.
    expect(find.text('That email and password don\'t match.'), findsOneWidget);

    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
  });

  testWidgets('recovery key screen blocks Continue until the user confirms',
      (tester) async {
    var done = false;
    await tester.pumpWidget(app(ZtRecoveryKeyScreen(
      recoveryKey: RecoveryKey.generate(),
      onDone: () => done = true,
    )));
    await settle(tester);

    final key =
        tester.widget<SelectableText>(find.byKey(const Key('zt-recovery-key')));
    expect(key.data, startsWith('ZT-'));

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    expect(done, isFalse);
    await tester.tap(find.text('I saved my recovery key somewhere safe'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    expect(done, isTrue);
  });

  testWidgets('unlock screen accepts the password and rejects a wrong one',
      (tester) async {
    await account.signUp(email: email, password: password);
    UnlockResult? result;
    await tester.pumpWidget(
        app(ZtUnlockScreen(email: email, onUnlocked: (r) => result = r)));
    expect(find.text('Zero-Trust Notes is locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not my password');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(result, isNull);
    expect(find.textContaining('can\'t unlock'), findsOneWidget);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(result, isNotNull);
  });

  testWidgets('unlock screen prompts for biometrics when they are on',
      (tester) async {
    final bio = InMemoryBiometricKeyStore();
    account = AccountService(backend, params: fast, biometrics: bio);
    final created = await account.signUp(email: email, password: password);
    await account.enableBiometrics(password);

    UnlockResult? result;
    await tester.pumpWidget(
        app(ZtUnlockScreen(email: email, onUnlocked: (r) => result = r)));
    await settle(tester);
    expect(result?.dek, created.dek);

    // Cancelled prompt: stays on the screen with the button to retry.
    result = null;
    bio.approve = false;
    await tester.pumpWidget(app(ZtUnlockScreen(
        key: const ValueKey(2), email: email, onUnlocked: (r) => result = r)));
    await settle(tester);
    expect(result, isNull);
    bio.approve = true;
    await tester.tap(find.text('Unlock with biometrics'));
    await settle(tester);
    expect(result?.dek, created.dek);
  });

  testWidgets('unlock screen explains a dropped biometric key', (tester) async {
    final bio = InMemoryBiometricKeyStore();
    account = AccountService(backend, params: fast, biometrics: bio);
    await account.signUp(email: email, password: password);
    await account.enableBiometrics(password);
    bio.invalidate(email);

    await tester
        .pumpWidget(app(ZtUnlockScreen(email: email, onUnlocked: (_) {})));
    await settle(tester);
    expect(find.textContaining('fingerprints or face changed'), findsOneWidget);
    expect(find.text('Unlock with biometrics'), findsNothing);
  });

  testWidgets('settings: biometric switch needs the password', (tester) async {
    final bio = InMemoryBiometricKeyStore();
    account = AccountService(backend, params: fast, biometrics: bio);
    await account.signUp(email: email, password: password);
    await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
    await settle(tester);

    final tile = find.widgetWithText(SwitchListTile, 'Unlock with biometrics');
    await tester.scrollUntilVisible(tile, 100);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Turn on'));
    await settle(tester);
    expect(await bio.isEnabled(email), isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await settle(tester);
    expect(await bio.isEnabled(email), isFalse);
  });

  testWidgets('settings: no biometric switch without hardware', (tester) async {
    account = AccountService(backend,
        params: fast, biometrics: InMemoryBiometricKeyStore(available: false));
    await account.signUp(email: email, password: password);
    await tester.pumpWidget(app(ZtSettingsPage(onSignedOut: () {})));
    await settle(tester);
    expect(find.text('Unlock with biometrics'), findsNothing);
  });

  testWidgets('forgot password sends the reset email', (tester) async {
    await tester.pumpWidget(app(const ZtForgotPasswordScreen()));
    await tester.enterText(find.byType(TextFormField), ' $email ');
    await tester
        .tap(find.widgetWithText(FilledButton, 'Email me a reset link'));
    await settle(tester);
    expect(backend.resetEmailsSent, [email]);
    expect(find.textContaining('Check $email'), findsOneWidget);
  });

  testWidgets('reset with the recovery key sets a new password',
      (tester) async {
    final created = await account.signUp(email: email, password: password);
    final recoveryText = await created.newRecoveryKey!.format();
    UnlockResult? result;
    await tester
        .pumpWidget(app(ZtResetPasswordScreen(onUnlocked: (r) => result = r)));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Recovery key'), recoveryText);
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'),
        'a brand new password');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'a brand new password');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await settle(tester);

    expect(result!.dek, created.dek);
    await tester.runAsync(() async {
      await account.signOut();
      await account.signIn(email: email, password: 'a brand new password');
    });
  });

  testWidgets('settings: theme switch, and delete needs the password',
      (tester) async {
    await account.signUp(email: email, password: password);
    var signedOut = 0;
    late WidgetRef ref;
    await tester.pumpWidget(app(Consumer(builder: (context, r, _) {
      ref = r;
      return ZtSettingsPage(
        onSignedOut: () => signedOut++,
        appSection: const [ListTile(title: Text('Default note color'))],
      );
    })));

    for (final header in [
      'Account',
      'Security',
      'Appearance',
      'About',
      'Danger zone'
    ]) {
      await tester.scrollUntilVisible(find.text(header), 100);
      expect(find.text(header), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Default note color'), -100);
    await tester.scrollUntilVisible(find.text(email), -100);

    await tester.scrollUntilVisible(find.text('Dark'), 100);
    await tester.ensureVisible(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(ref.read(themeModeProvider), ThemeMode.dark);

    // Delete with the wrong password does nothing.
    await tester.scrollUntilVisible(find.text('Delete account'), 100);
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not my password');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(backend.profiles, contains(email));
    expect(signedOut, 0);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(backend.profiles, isNot(contains(email)));
    expect(signedOut, 1);
  });
}
