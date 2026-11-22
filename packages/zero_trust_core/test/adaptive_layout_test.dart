import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

/// S-11: phone, unfolded foldable and tablet layouts.
void main() {
  Future<void> setWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('window classes follow Material 3', () {
    expect(ZtWindowClass.forWidth(411), ZtWindowClass.compact);
    expect(ZtWindowClass.forWidth(600), ZtWindowClass.medium);
    expect(ZtWindowClass.forWidth(839), ZtWindowClass.medium);
    expect(ZtWindowClass.forWidth(1280), ZtWindowClass.expanded);
  });

  test('readable padding centres content only when there is room', () {
    expect(ZtLayout.readablePadding(const BoxConstraints(maxWidth: 400)),
        EdgeInsets.zero);
    final wide = ZtLayout.readablePadding(const BoxConstraints(maxWidth: 1280),
        base: const EdgeInsets.all(24));
    expect(wide.left, 24 + (1280 - 48 - 720) / 2);
    expect(wide.right, wide.left);
    expect(wide.top, 24);
  });

  group('settings', () {
    Widget app() => ProviderScope(
          overrides: [
            accountServiceProvider
                .overrideWithValue(AccountService(FakeBackend(), params: fast)),
            ztPreferencesStoreProvider
                .overrideWithValue(InMemoryPreferencesStore()),
            ztAppConfigProvider.overrideWithValue(const ZtAppConfig(
                appId: 'notes', displayName: 'Zero-Trust Notes')),
          ],
          child: MaterialApp(
            theme: ZtTheme.light(),
            localizationsDelegates: ZtLanguages.delegates,
            supportedLocales: ZtL10n.supportedLocales,
            home: ZtSettingsPage(onSignedOut: () {}, accountOptional: true),
          ),
        );

    testWidgets('on a tablet the list is centred and readable', (tester) async {
      await setWindow(tester, const Size(1280, 420));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final row = tester.getRect(find.widgetWithText(ListTile, 'Light'));
      expect(row.width, lessThanOrEqualTo(ZtLayout.readableWidth + 0.01));
      expect(row.left, closeTo((1280 - row.width) / 2, 0.5));
      // Scrolling still works from the margin.
      await tester.dragFrom(const Offset(40, 300), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.widgetWithText(ListTile, 'Light')).top,
          lessThan(row.top));
    });

    testWidgets('on a phone it uses the whole width', (tester) async {
      await setWindow(tester, const Size(411, 900));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final row = tester.getRect(find.widgetWithText(ListTile, 'Light'));
      expect(row.left, 0);
      expect(row.width, 411);
    });
  });

  group('two panes', () {
    Widget panes({TextDirection dir = TextDirection.ltr}) => MaterialApp(
          home: Directionality(
            textDirection: dir,
            child: const Scaffold(
              body: ZtTwoPane(
                list: ColoredBox(color: Colors.red, key: Key('list')),
                detail: ColoredBox(color: Colors.blue, key: Key('detail')),
              ),
            ),
          ),
        );

    testWidgets('a phone shows only the list', (tester) async {
      await setWindow(tester, const Size(411, 900));
      await tester.pumpWidget(panes());
      expect(find.byKey(const Key('list')), findsOneWidget);
      expect(find.byKey(const Key('detail')), findsNothing);
      expect(ZtTwoPane.showsBoth(tester.element(find.byKey(const Key('list')))),
          isFalse);
    });

    testWidgets('a tablet shows list and detail', (tester) async {
      await setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(panes());
      final list = tester.getRect(find.byKey(const Key('list')));
      final detail = tester.getRect(find.byKey(const Key('detail')));
      expect(list.left, 0);
      expect(list.width, ZtLayout.listPaneWidth);
      expect(detail.left, greaterThanOrEqualTo(list.right));
      expect(detail.right, 1280);
    });

    for (final dir in TextDirection.values) {
      testWidgets('an open foldable splits at the hinge (${dir.name})',
          (tester) async {
        await setWindow(tester, const Size(1260, 840));
        tester.view.displayFeatures = [
          const DisplayFeature(
            bounds: Rect.fromLTWH(615, 0, 30, 840),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ];
        addTearDown(tester.view.resetDisplayFeatures);
        await tester.pumpWidget(panes(dir: dir));
        final list = tester.getRect(find.byKey(const Key('list')));
        final detail = tester.getRect(find.byKey(const Key('detail')));
        if (dir == TextDirection.ltr) {
          expect(list.left, 0);
          expect(list.right, 615);
          expect(detail.left, 645);
          expect(detail.right, 1260);
        } else {
          // Hebrew: the list starts on the right.
          expect(list.left, 645);
          expect(list.right, 1260);
          expect(detail.left, 0);
          expect(detail.right, 615);
        }
        expect(
            ZtTwoPane.showsBoth(tester.element(find.byKey(const Key('list')))),
            isTrue);
      });
    }

    testWidgets('a narrow window with a cutout is still one pane',
        (tester) async {
      await setWindow(tester, const Size(411, 900));
      tester.view.displayFeatures = [
        const DisplayFeature(
          bounds: Rect.fromLTWH(180, 0, 50, 30),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ];
      addTearDown(tester.view.resetDisplayFeatures);
      await tester.pumpWidget(panes());
      expect(find.byKey(const Key('detail')), findsNothing);
    });
  });
}
