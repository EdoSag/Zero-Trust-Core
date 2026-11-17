import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

void main() {
  group('ZtInstallChannel', () {
    test('reads the build flag', () {
      expect(ZtInstallChannel.fromName('direct'), ZtInstallChannel.direct);
      expect(ZtInstallChannel.fromName('play'), ZtInstallChannel.play);
      expect(ZtInstallChannel.fromName('appStore'), ZtInstallChannel.appStore);
    });

    test('without a flag a build counts as a store build', () {
      expect(ZtInstallChannel.fromName(null, platform: TargetPlatform.android),
          ZtInstallChannel.play);
      expect(ZtInstallChannel.fromName('typo', platform: TargetPlatform.iOS),
          ZtInstallChannel.appStore);
      expect(ZtInstallChannel.current, ZtInstallChannel.play,
          reason: 'tests run without ZT_CHANNEL');
    });

    test('only direct builds may link to outside payments', () {
      expect(ZtInstallChannel.direct.allowsExternalPayments, isTrue);
      expect(ZtInstallChannel.play.allowsExternalPayments, isFalse);
      expect(ZtInstallChannel.appStore.allowsExternalPayments, isFalse);
    });
  });

  group('sponsor row in settings', () {
    Widget app(ZtInstallChannel channel, List<Uri> opened,
            {bool showSponsor = true}) =>
        ProviderScope(
          overrides: [
            accountServiceProvider.overrideWithValue(AccountService(
                FakeBackend(),
                params: fast,
                legacyParams: fast)),
            ztPreferencesStoreProvider
                .overrideWithValue(InMemoryPreferencesStore()),
            ztAppConfigProvider.overrideWithValue(ZtAppConfig(
                appId: 'notes',
                displayName: 'Zero-Trust Notes',
                channel: channel)),
          ],
          child: MaterialApp(
            theme: ZtTheme.light(),
            home: ZtSettingsPage(
              onSignedOut: () {},
              onOpenUrl: opened.add,
              showSponsor: showSponsor,
            ),
          ),
        );

    Future<Finder> findRow(WidgetTester tester) async {
      final row = find.text('Support the project');
      // The row sits right above Privacy policy, which every build shows
      // once the app can open links.
      await tester.scrollUntilVisible(find.text('Privacy policy'), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      return row;
    }

    testWidgets('direct builds show it and open GitHub Sponsors',
        (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(app(ZtInstallChannel.direct, opened));
      await tester.pumpAndSettle();
      final row = await findRow(tester);
      expect(row, findsOneWidget);
      await tester.tap(row);
      expect(opened, [Uri.parse('https://github.com/sponsors/EdoSag')]);
    });

    for (final store in [ZtInstallChannel.play, ZtInstallChannel.appStore]) {
      testWidgets('${store.name} builds never show it', (tester) async {
        await tester.pumpWidget(app(store, []));
        await tester.pumpAndSettle();
        expect(await findRow(tester), findsNothing);
      });
    }

    testWidgets('apps can turn it off', (tester) async {
      await tester
          .pumpWidget(app(ZtInstallChannel.direct, [], showSponsor: false));
      await tester.pumpAndSettle();
      expect(await findRow(tester), findsNothing);
    });
  });
}
