import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

// The core package's own test fakes.
import '../../zero_trust_core/test/support/fake_backend.dart';
import '../../zero_trust_core/test/support/fake_sync_backend.dart';

const alice = '00000000-0000-4000-8000-00000000000a';
const bob = '00000000-0000-4000-8000-00000000000b';

class _Account extends AccountService {
  _Account(this.id) : super(FakeBackend());
  final String id;
  @override
  String? get currentUserId => id;
}

class _MemoryOpener implements SpaceStoreOpener {
  final Map<String, InMemoryItemStore> stores = {};
  @override
  Future<LocalItemStore> open(String spaceId) async =>
      stores.putIfAbsent(spaceId, InMemoryItemStore.new);
  @override
  Future<void> delete(String spaceId) async => stores.remove(spaceId);
  @override
  Future<void> closeAll() async {}
}

void main() {
  late InMemorySpaceServer server;

  ProviderContainer phone(String userId, {String appId = 'notes'}) {
    final c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          ZtAppConfig(appId: appId, displayName: 'Zero-Trust Notes')),
      accountServiceProvider.overrideWithValue(_Account(userId)),
      ztSyncBackendProvider.overrideWithValue(
          FakeSyncBackend()..serverNow = () => DateTime.now().toUtc()),
      ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()),
      ztLocalStoreProvider.overrideWith((ref) async {
        final appKey = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (appKey == null) throw const VaultIsLocked();
        final store = await ZtLocalStore.open(appKey: appKey);
        ref.onDispose(store.close);
        return store;
      }),
      ztSpaceBackendProvider.overrideWithValue(server.backendFor(userId)),
      ztSpaceStoreOpenerProvider.overrideWithValue(_MemoryOpener()),
    ]);
    addTearDown(c.dispose);
    c.listen(ztSyncControllerProvider, (_, __) {});
    c.listen(ztSpacesProvider, (_, __) {});
    return c;
  }

  Future<void> until(
      ProviderContainer c, bool Function(SpacesState) test) async {
    for (var i = 0; i < 400; i++) {
      if (test(c.read(ztSpacesProvider))) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('spaces never settled: ${c.read(ztSpacesProvider).entries}');
  }

  Future<ProviderContainer> unlocked(String userId, int seed,
      {String appId = 'notes'}) async {
    final c = phone(userId, appId: appId);
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, seed)));
    await until(c, (s) => s.ready && !s.loading);
    return c;
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c, Widget home,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      key: UniqueKey(),
      container: c,
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('he')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ZtTheme.light(),
        home: home,
      ),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void expectOnScreen(WidgetTester tester, Key key) {
    final rect = tester.getRect(find.byKey(key));
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.width, greaterThan(40), reason: '$key has no width');
    expect(screen.contains(rect.center), isTrue, reason: '$key at $rect');
    expect(find.byKey(key).hitTestable(), findsOneWidget);
  }

  /// Closes both phones so no sync timer outlives the test.
  Future<void> done(WidgetTester tester, List<ProviderContainer> phones) async {
    await tester.pumpWidget(const SizedBox());
    for (final c in phones) {
      c.dispose();
    }
    await tester.pump(const Duration(minutes: 10));
  }

  setUp(() => server = InMemorySpaceServer());

  test('strings follow the locale', () {
    expect(ZtSharingStrings.forLocale(const Locale('he')).join, 'הצטרפות');
    expect(ZtSharingStrings.forLocale(const Locale('fr')).join, 'Join');
    expect(ZtSharingStrings.en.deleteQ('Trip'), 'Delete “Trip” for everyone?');
  });

  testWidgets('invite, join with the link, compare codes, let in',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    late ProviderContainer a, b;
    late String spaceId;
    late SpaceInviteLink link;
    await tester.runAsync(() async {
      a = await unlocked(alice, 1);
      b = await unlocked(bob, 2);
      final space =
          await a.read(ztSpacesProvider.notifier).create(myName: 'Alice');
      spaceId = space.id;
    });

    // Alice's space page, then the invite.
    await pump(tester, a,
        ZtSpacePage(spaceId: spaceId, title: 'Trip', inviteNow: true));
    await settle(tester);
    expect(find.text('Invite to “Trip”'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('zt-invite-create')));
      for (var i = 0;
          i < 20 && find.byKey(const Key('zt-invite-qr')).evaluate().isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(find.byKey(const Key('zt-invite-qr')), findsOneWidget);
    expectOnScreen(tester, const Key('zt-invite-copy'));
    expectOnScreen(tester, const Key('zt-invite-send'));
    final copy = tester.getRect(find.byKey(const Key('zt-invite-copy')));
    final send = tester.getRect(find.byKey(const Key('zt-invite-send')));
    expect(copy.overlaps(send), isFalse);
    expect((copy.center.dy - send.center.dy).abs(), lessThan(1));
    link = (await tester.runAsync(() => a
        .read(ztSpacesProvider.notifier)
        .invite(spaceId)))!; // A second, fresh invite for Bob below.

    // Bob joins on his phone.
    await pump(tester, b, const ZtJoinSpacePage());
    await tester.enterText(
        find.byKey(const Key('zt-join-link')), 'https://example.com/x');
    await tester.enterText(find.byKey(const Key('zt-join-name')), 'Bob');
    await tester.tap(find.byKey(const Key('zt-join-submit')));
    await tester.pump();
    expect(
        find.text("That's not a Zero-Trust Notes invite link"), findsOneWidget);
    await tester.enterText(find.byKey(const Key('zt-join-link')), '$link');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('zt-join-submit')));
      for (var i = 0;
          i < 40 && find.byKey(const Key('zt-join-code')).evaluate().isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    final code =
        tester.widget<Text>(find.byKey(const Key('zt-join-code'))).data!;
    expect(code, isNotEmpty);
    expect(await tester.runAsync(() => b.read(ztSharingNameProvider).read()),
        'Bob');

    // Alice sees the request on her home screen and lets Bob in.
    await pump(
        tester,
        a,
        Scaffold(
            body: ListView(children: [
          ZtJoinRequestCards(titleOf: (_) => 'Trip'),
        ])));
    await settle(tester);
    expect(find.text('Bob wants to join “Trip”'), findsOneWidget);
    await tester.tap(find.text('Bob wants to join “Trip”'));
    await tester.pumpAndSettle();
    expect(find.text(code), findsOneWidget, reason: 'same code on both');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('zt-codes-match')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(find.text('Bob wants to join “Trip”'), findsNothing);

    // Both are members; Alice sees Bob on the space page.
    await tester.runAsync(() async {
      await until(b, (s) => s[spaceId]?.space != null);
    });
    await pump(tester, a, ZtSpacePage(spaceId: spaceId, title: 'Trip'));
    await settle(tester);
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('Alice (you)'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expectOnScreen(tester, const Key('zt-space-invite'));
    await done(tester, [a, b]);
  });

  testWidgets('an invite from another app is refused, in Hebrew too',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    late ProviderContainer a, b;
    late SpaceInviteLink link;
    await tester.runAsync(() async {
      a = await unlocked(alice, 1, appId: 'tasks');
      b = await unlocked(bob, 2);
      final spaces = a.read(ztSpacesProvider.notifier);
      final space = await spaces.create(myName: 'Alice');
      link = await spaces.invite(space.id);
    });
    await pump(tester, b, ZtJoinSpacePage(initialLink: '$link'),
        locale: const Locale('he'));
    await tester.enterText(find.byKey(const Key('zt-join-name')), 'בוב');
    await tester.tap(find.byKey(const Key('zt-join-submit')));
    await tester.pump();
    expect(find.text(ZtSharingStrings.he.inviteOtherApp), findsOneWidget);
    expect(
        Directionality.of(
            tester.element(find.byKey(const Key('zt-join-name')))),
        TextDirection.rtl);
    await done(tester, [a, b]);
  });
}
