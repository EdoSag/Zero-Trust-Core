import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';
import 'support/fake_handoff.dart';

/// S-2: sign in once per phone. One Zero-Trust app opens with the account
/// another app on the phone is signed in to, without the password.
void main() {
  const email = 'edo@example.com';
  const password = 'correct horse battery';
  final notesPkg = ZtSuite.notes.androidPackage;
  final calendarPkg = ZtSuite.calendar.androidPackage;

  late FakePhone phone;
  late HandoffServer server;
  late HandoffFakeBackend notesBackend;
  late HandoffFakeBackend calendarBackend;
  late AccountService notes;
  late AccountService calendar;
  late FakeHandoffChannel notesChannel;
  late FakeHandoffChannel calendarChannel;
  late ZtSignInHandoff notesHandoff;
  late ZtSignInHandoff calendarHandoff;

  setUp(() {
    phone = FakePhone();
    server = HandoffServer();
    notesBackend = HandoffFakeBackend(server);
    calendarBackend = HandoffFakeBackend(server);
    notes = AccountService(notesBackend, params: fast, legacyParams: fast);
    calendar =
        AccountService(calendarBackend, params: fast, legacyParams: fast);
    notesChannel = phone.install(notesPkg);
    calendarChannel = phone.install(calendarPkg);
    notesHandoff = ZtSignInHandoff(notesChannel);
    calendarHandoff = ZtSignInHandoff(calendarChannel);
  });

  tearDown(() {
    notesHandoff.dispose();
    calendarHandoff.dispose();
  });

  ZtHandoffApp notesApp() => ZtHandoffApp(ZtSuite.notes, notesPkg);

  /// What ZtSignInHandoffScope does in Notes once the person allows it.
  StreamSubscription<ZtHandoffRequest> notesAllows(
          {Duration validFor = const Duration(minutes: 2)}) =>
      notesHandoff.requests.listen((r) async {
        final proof = await notes.unlock(password);
        final grant = await notes.handoffGrant(proof,
            withSession: r.mode == ZtHandoffMode.signIn, validFor: validFor);
        proof.dek.fillRange(0, proof.dek.length, 0);
        await notesHandoff.answer(r, grant);
        grant.wipe();
      });

  bool containsBytes(List<int> haystack, List<int> needle) {
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length && match; j++) {
        match = haystack[i + j] == needle[j];
      }
      if (match) return true;
    }
    return false;
  }

  group('handing the account over', () {
    test('Calendar signs in with the account Notes is signed in to', () async {
      final created = await notes.signUp(email: email, password: password);
      final dek = Uint8List.fromList(created.dek);
      notesAllows();

      final givers = await calendarHandoff.givers();
      expect(givers.map((g) => g.label), ['ZT Notes']);
      final grant =
          await calendarHandoff.ask(givers.single, ZtHandoffMode.signIn);
      final result = await calendar.signInWithHandoff(grant);
      grant.wipe();

      expect(result.dek, dek);
      expect(result.legacyDek, isFalse);
      expect(calendar.currentUserId, email);
      // Its own session: Notes stays signed in, and the token is used up.
      expect(notes.currentUserId, email);
      expect(server.tokens, isEmpty);
      expect(server.tokensMade, 1);
      // Nothing that travelled between the apps holds the key in the clear.
      expect(phone.sent, hasLength(2));
      for (final m in phone.sent) {
        expect(containsBytes(m.payload, dek), isFalse);
      }
      // Calendar kept the key row, so it unlocks with the password later.
      final again = await calendar.unlock(password);
      expect(again.dek, dek);
    });

    test('an account from before the core keeps its old data key', () async {
      final oldKey =
          await notesBackend.seedUpgradedLegacyAccount(email, password);
      await notes.signIn(email: email, password: password);
      notesAllows();

      final grant = await calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn);
      final result = await calendar.signInWithHandoff(grant);

      expect(result.dek, oldKey);
      expect(result.legacyDek, isTrue);
    });

    test('unlocking needs no server: only the key travels', () async {
      final created = await notes.signUp(email: email, password: password);
      await calendar.signIn(email: email, password: password);
      notesAllows();

      final grant = await calendarHandoff.ask(notesApp(), ZtHandoffMode.unlock);
      expect(grant.tokenHash, isNull);
      expect(calendar.unlockWithHandoff(grant).dek, created.dek);
      expect(server.tokensMade, 0);
    });

    test('unlocking with another account is refused', () async {
      await notes.signUp(email: email, password: password);
      await calendar.signUp(email: 'other@example.com', password: password);
      notesAllows();

      final grant = await calendarHandoff.ask(notesApp(), ZtHandoffMode.unlock);
      expect(() => calendar.unlockWithHandoff(grant),
          throwsA(isA<ZtHandoffWrongAccount>()));
    });

    test('a token for another account leaves the app signed out', () async {
      await notes.signUp(email: email, password: password);
      final proof = await notes.unlock(password);
      final grant = await notes.handoffGrant(proof, withSession: true);
      server.tokens[grant.tokenHash!] = 'someone@else.com';

      await expectLater(calendar.signInWithHandoff(grant),
          throwsA(isA<ZtHandoffWrongAccount>()));
      expect(calendar.currentUserId, isNull);
    });

    test('says no when the other app says no, and why', () async {
      await notes.signUp(email: email, password: password);
      notesHandoff.requests
          .listen((r) => notesHandoff.refuse(r, ZtHandoffRefusal.signedOut));

      await expectLater(
        calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn),
        throwsA(isA<ZtHandoffRefused>()
            .having((e) => e.reason, 'reason', ZtHandoffRefusal.signedOut)
            .having((e) => e.app.label, 'app', 'ZT Notes')),
      );
      expect(
          ztErrorMessage(
              ZtHandoffRefused(notesApp(), ZtHandoffRefusal.declined)),
          "ZT Notes didn't share the account.");
    });

    test('an expired grant is not used', () async {
      await notes.signUp(email: email, password: password);
      notesAllows(validFor: const Duration(seconds: -1));

      await expectLater(
        calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn),
        throwsA(isA<ZtHandoffRefused>()
            .having((e) => e.reason, 'reason', ZtHandoffRefusal.failed)),
      );
    });

    test('a request that came in before anyone listened is kept', () async {
      await notes.signUp(email: email, password: password);
      final asked = calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      notesAllows();
      final grant = await asked;
      expect(grant.userId, email);
    });

    test('Cancel stops waiting', () async {
      final asked = calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn);
      await Future<void>.delayed(Duration.zero);
      calendarHandoff.cancel();
      await expectLater(asked, throwsA(isA<ZtHandoffCancelled>()));
    });
  });

  group('only Zero-Trust apps take part', () {
    test('lists installed apps with the same signature, never itself',
        () async {
      phone.install(ZtSuite.tasks.androidPackage);
      phone.install(ZtSuite.phone.androidPackage, signature: 'someone else');
      phone.install('com.example.spy', signature: 'spy');
      expect((await notesHandoff.givers()).map((g) => g.label),
          ['ZT Tasks', 'ZT Calendar']);
      expect(
          await ZtSignInHandoff(
                  phone.install('com.example.spy', signature: 'spy'))
              .givers(),
          isEmpty);
    });

    test('an answer not sealed for this request is ignored', () async {
      final waiting = ZtSignInHandoff(
          phone.install(ZtSuite.meds.androidPackage),
          timeout: const Duration(milliseconds: 300));
      addTearDown(waiting.dispose);
      final asked = waiting.ask(notesApp(), ZtHandoffMode.signIn);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Another app with the same signature makes up an answer.
      final forged = await SealedBox.seal([1, 2, 3], Uint8List(32), aad: [1]);
      phone.deliver(
          ZtSuite.meds.androidPackage,
          ZtHandoffMessage(
              kind: 'answer',
              from: notesPkg,
              mode: 'signIn',
              payload: forged,
              at: DateTime.now()));
      await expectLater(asked, throwsA(isA<TimeoutException>()));
    });

    test('requests from apps outside the suite or from long ago are dropped',
        () async {
      final heard = <ZtHandoffRequest>[];
      notesHandoff.requests.listen(heard.add);
      // Same signature, but not a Zero-Trust app the suite knows.
      phone.install('dev.sagron.experiment');
      phone.deliver(
          notesPkg,
          ZtHandoffMessage(
              kind: 'request',
              from: 'dev.sagron.experiment',
              mode: 'signIn',
              payload: Uint8List(32),
              at: DateTime.now()));
      // An old request, from before a restart.
      phone.deliver(
          notesPkg,
          ZtHandoffMessage(
              kind: 'request',
              from: calendarPkg,
              mode: 'signIn',
              payload: Uint8List(32),
              at: DateTime.now().subtract(const Duration(minutes: 10))));
      // A different signature never gets through at all.
      phone.install('com.example.spy', signature: 'spy');
      phone.deliver(
          notesPkg,
          ZtHandoffMessage(
              kind: 'request',
              from: 'com.example.spy',
              mode: 'signIn',
              payload: Uint8List(32),
              at: DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(heard, isEmpty);
    });

    test('the Android manifest can see every app in the suite', () {
      final manifest =
          File('android/src/main/AndroidManifest.xml').readAsStringSync();
      final listed = RegExp(r'<package android:name="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(listed, {for (final a in ZtSuite.apps) a.androidPackage});
    });

    test('a grant survives the trip and nothing else decodes', () {
      final grant = ZtHandoffGrant(
        userId: 'u1',
        email: email,
        dek: Uint8List.fromList(List.generate(32, (i) => i)),
        legacyDek: true,
        tokenHash: 'abc',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      final back = ZtHandoffGrant.decode(grant.encode());
      expect(back.userId, 'u1');
      expect(back.email, email);
      expect(back.dek, grant.dek);
      expect(back.legacyDek, isTrue);
      expect(back.tokenHash, 'abc');
      expect(back.expiresAt, grant.expiresAt);
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList([2, 0, 32]),
        Uint8List.fromList([1, 0, 200, 1, 2]),
      ]) {
        expect(() => ZtHandoffGrant.decode(bad), throwsFormatException);
      }
    });
  });

  group('screens', () {
    Widget app(Widget home,
            {required AccountService account,
            required ZtSignInHandoff handoff,
            required String appId}) =>
        ProviderScope(
          overrides: [
            accountServiceProvider.overrideWithValue(account),
            // One handoff per app, as the app's own provider makes it.
            ztSignInHandoffProvider.overrideWithValue(handoff),
            ztPreferencesStoreProvider
                .overrideWithValue(InMemoryPreferencesStore()),
            ztAppConfigProvider.overrideWithValue(
                ZtAppConfig(appId: appId, displayName: 'Zero-Trust $appId')),
          ],
          child: MaterialApp(
            theme: ZtTheme.light(),
            localizationsDelegates: ZtLanguages.delegates,
            supportedLocales: ZtL10n.supportedLocales,
            home: home,
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        // Moves the fake clock too: messages between apps go on timers.
        await tester.pump(const Duration(milliseconds: 20));
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

    testWidgets('"Sign in with ZT Notes" under Sign in, and it signs in',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final created = await tester
          .runAsync(() => notes.signUp(email: email, password: password));
      notesAllows();
      UnlockResult? got;
      await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (r) => got = r),
          account: calendar, handoff: calendarHandoff, appId: 'calendar'));
      await settle(tester);

      final button =
          find.widgetWithText(OutlinedButton, 'Sign in with ZT Notes');
      expectOnScreen(tester, button);
      final signIn = find.widgetWithText(FilledButton, 'Sign in');
      expect(tester.getRect(button).top,
          greaterThanOrEqualTo(tester.getRect(signIn).bottom));
      expect(tester.getRect(button).width, tester.getRect(signIn).width);

      await tester.tap(button);
      await tester.pump();
      expect(find.text('Confirm in ZT Notes…'), findsOneWidget);
      await settle(tester);

      expect(got?.dek, created!.dek);
      expect(calendar.currentUserId, email);
    });

    testWidgets('no button when no other Zero-Trust app is installed',
        (tester) async {
      final alone = ZtSignInHandoff(FakePhone().install(calendarPkg));
      addTearDown(alone.dispose);
      await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {}),
          account: calendar, handoff: alone, appId: 'calendar'));
      await settle(tester);
      expect(find.textContaining('ZT Notes'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('a refusal shows why on the sign-in screen', (tester) async {
      notesHandoff.requests
          .listen((r) => notesHandoff.refuse(r, ZtHandoffRefusal.signedOut));
      await tester.pumpWidget(app(ZtSignInScreen(onUnlocked: (_) {}),
          account: calendar, handoff: calendarHandoff, appId: 'calendar'));
      await settle(tester);
      await tester.tap(find.text('Sign in with ZT Notes'));
      await settle(tester);
      final message = find.text(
          "ZT Notes isn't signed in. Sign in there first, or use your password here.");
      expectOnScreen(tester, message);
      expect(find.text('Sign in with ZT Notes'), findsOneWidget);
    });

    testWidgets('Notes asks, checks the password, then hands it over',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester
          .runAsync(() => notes.signUp(email: email, password: password));
      await tester.pumpWidget(app(
          const ZtSignInHandoffScope(child: Text('Notes home')),
          account: notes,
          handoff: notesHandoff,
          appId: 'notes'));
      await settle(tester);

      final asked = calendarHandoff.ask(notesApp(), ZtHandoffMode.signIn);
      ZtHandoffGrant? grant;
      unawaited(asked.then((g) => grant = g));
      await settle(tester);

      expect(find.text('Sign in to ZT Calendar?'), findsOneWidget);
      expect(find.textContaining(email), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await settle(tester);
      // Biometrics are off here, so the password.
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await settle(tester);

      expect(grant, isNotNull);
      expect(grant!.userId, email);
      expect(grant!.tokenHash, isNotNull);
      expect(find.text('Notes home'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Not now refuses', (tester) async {
      await tester
          .runAsync(() => notes.signUp(email: email, password: password));
      await tester.pumpWidget(app(
          const ZtSignInHandoffScope(child: Text('Notes home')),
          account: notes,
          handoff: notesHandoff,
          appId: 'notes'));
      await settle(tester);
      Object? error;
      unawaited(calendarHandoff
          .ask(notesApp(), ZtHandoffMode.signIn)
          .then<void>((_) {}, onError: (Object e) => error = e));
      await settle(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(error, isA<ZtHandoffRefused>());
      expect((error! as ZtHandoffRefused).reason, ZtHandoffRefusal.declined);
    });

    testWidgets('a server that refuses shows a message in Notes',
        (tester) async {
      await tester
          .runAsync(() => notes.signUp(email: email, password: password));
      server.functionMissing = true;
      await tester.pumpWidget(app(
          const Scaffold(body: ZtSignInHandoffScope(child: Text('Notes home'))),
          account: notes,
          handoff: notesHandoff,
          appId: 'notes'));
      await settle(tester);
      Object? error;
      unawaited(calendarHandoff
          .ask(notesApp(), ZtHandoffMode.signIn)
          .then<void>((_) {}, onError: (Object e) => error = e));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await settle(tester);
      expect((error! as ZtHandoffRefused).reason, ZtHandoffRefusal.failed);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a signed-out Notes says so without asking', (tester) async {
      await tester.pumpWidget(app(
          const ZtSignInHandoffScope(child: Text('Notes home')),
          account: notes,
          handoff: notesHandoff,
          appId: 'notes'));
      await settle(tester);
      Object? error;
      unawaited(calendarHandoff
          .ask(notesApp(), ZtHandoffMode.signIn)
          .then<void>((_) {}, onError: (Object e) => error = e));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect((error! as ZtHandoffRefused).reason, ZtHandoffRefusal.signedOut);
    });

    testWidgets('"Unlock with ZT Notes" on the lock screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final created = await tester
          .runAsync(() => notes.signUp(email: email, password: password));
      await tester
          .runAsync(() => calendar.signIn(email: email, password: password));
      notesAllows();
      UnlockResult? got;
      await tester.pumpWidget(app(
          ZtUnlockScreen(email: email, onUnlocked: (r) => got = r),
          account: calendar,
          handoff: calendarHandoff,
          appId: 'calendar'));
      await settle(tester);

      final button =
          find.widgetWithText(OutlinedButton, 'Unlock with ZT Notes');
      expectOnScreen(tester, button);
      expect(
          tester.getRect(button).top,
          greaterThanOrEqualTo(tester
              .getRect(find.widgetWithText(FilledButton, 'Unlock'))
              .bottom));
      await tester.tap(button);
      await settle(tester);
      expect(got?.dek, created!.dek);
      expect(server.tokensMade, 0);
    });
  });
}
