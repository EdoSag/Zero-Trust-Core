import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

class _FakePlan implements PlanSource {
  _FakePlan(this.plan);
  ZtPlan? plan;
  var fetches = 0;
  @override
  Future<ZtPlan?> fetch() async {
    fetches++;
    return plan;
  }
}

/// A store whose purchase finishes only when the test says so.
class _SlowStore extends FakeBillingStore {
  final done = Completer<ZtPurchaseOutcome>();
  @override
  Future<ZtPurchaseOutcome> buy(ZtStoreOffer offer) => done.future;
}

class _Vault extends VaultController {
  @override
  VaultState build() => VaultUnlocked(appKey: Uint8List(32));
}

const _plus = ZtPlan(
  id: 'plus',
  names: {'en': 'Plus', 'he': 'פלוס'},
  status: ZtPlanStatus.active,
  source: ZtPlanSource.googlePlay,
);

void main() {
  Widget app(_FakePlan plan, ZtBillingStore? store,
          {Locale? locale, void Function(Uri)? onOpenUrl}) =>
      ProviderScope(
        overrides: [
          ztPlanSourceProvider.overrideWithValue(plan),
          vaultControllerProvider.overrideWith(_Vault.new),
          ztBillingStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: ZtLanguages.delegates,
          theme: ZtTheme.light(),
          home: ZtPlansScreen(
              termsUrl: Uri.parse('https://zerotrust.bz/terms/'),
              onOpenUrl: onOpenUrl),
        ),
      );

  testWidgets('free account sees store prices, yearly first in weight',
      (tester) async {
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), FakeBillingStore()));
    await tester.pumpAndSettle();
    expect(find.text('Plan: Free'), findsOneWidget);
    expect(find.text(r'$2.99 a month'), findsOneWidget);
    expect(find.text(r'$29.00 a year'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text(r'$29.00 a year'),
            matching: find.byType(FilledButton)),
        findsOneWidget);
    // Monthly sits above yearly.
    expect(tester.getTopLeft(find.text(r'$2.99 a month')).dy,
        lessThan(tester.getTopLeft(find.text(r'$29.00 a year')).dy));
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.textContaining('No free trial'), findsOneWidget);
    expect(find.text('Manage subscription'), findsNothing);
  });

  testWidgets('buying turns Plus on and reloads the plan', (tester) async {
    final plan = _FakePlan(ZtPlan.free);
    final store = FakeBillingStore(onPurchased: (_) => plan.plan = _plus);
    await tester.pumpWidget(app(plan, store));
    await tester.pumpAndSettle();
    final before = plan.fetches;
    await tester.tap(find.text(r'$29.00 a year'));
    await tester.pumpAndSettle();
    expect(store.bought.single.period, ZtBillingPeriod.year);
    expect(plan.fetches, greaterThan(before));
    expect(find.text('Thank you! Plus is on.'), findsOneWidget);
    expect(find.text('Plan: Plus'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.text(r'$29.00 a year'), findsNothing);
  });

  testWidgets('pending, failed and cancelled purchases', (tester) async {
    final store = FakeBillingStore(outcome: ZtPurchaseOutcome.pending);
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$2.99 a month'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Payment pending'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(ZtPlansScreen)))
        .removeCurrentSnackBar();
    store.outcome = ZtPurchaseOutcome.failed;
    await tester.tap(find.text(r'$2.99 a month'));
    await tester.pumpAndSettle();
    expect(find.text("The purchase didn't go through. Please try again."),
        findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(ZtPlansScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    store.outcome = ZtPurchaseOutcome.canceled;
    await tester.tap(find.text(r'$2.99 a month'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(store.bought, isEmpty);
    expect(find.text('Plan: Free'), findsOneWidget);
  });

  testWidgets('restore and manage reach the store', (tester) async {
    final store = FakeBillingStore();
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(store.restored, 1);

    await tester.pumpWidget(app(_FakePlan(_plus), store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage subscription'));
    await tester.pumpAndSettle();
    expect(store.managed, 1);
  });

  testWidgets('no store in this build: nothing to buy', (tester) async {
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), null));
    await tester.pumpAndSettle();
    expect(find.text("Plus can't be bought here yet."), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
  });

  testWidgets('store with nothing for sale yet', (tester) async {
    await tester.pumpWidget(
        app(_FakePlan(ZtPlan.free), FakeBillingStore(offers: const [])));
    await tester.pumpAndSettle();
    expect(find.text("Plus can't be bought here yet."), findsOneWidget);
  });

  testWidgets('a granted plan has no manage button', (tester) async {
    const granted = ZtPlan(
        id: 'plus',
        names: {'en': 'Plus'},
        status: ZtPlanStatus.active,
        source: ZtPlanSource.manual);
    await tester.pumpWidget(app(_FakePlan(granted), FakeBillingStore()));
    await tester.pumpAndSettle();
    expect(find.text('Plus was given to you by Zero-Trust.'), findsOneWidget);
    expect(find.text('Manage subscription'), findsNothing);
  });

  testWidgets('terms link opens the terms page', (tester) async {
    Uri? opened;
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), FakeBillingStore(),
        onOpenUrl: (u) => opened = u));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Terms of use'), 100);
    await tester.tap(find.text('Terms of use'));
    expect(opened, Uri.parse('https://zerotrust.bz/terms/'));
  });

  testWidgets('Hebrew is right to left', (tester) async {
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), FakeBillingStore(),
        locale: const Locale('he')));
    await tester.pumpAndSettle();
    expect(find.text('תוכניות'), findsOneWidget);
    expect(find.text(r'$29.00 לשנה'), findsOneWidget);
    final check = tester.getTopLeft(find.byIcon(Icons.check).first).dx;
    final text = tester.getTopLeft(find.text('מינוי אחד לכל האפליקציות')).dx;
    expect(check, greaterThan(text));
  });

  testWidgets('leaving the screen during a purchase is safe', (tester) async {
    final store = _SlowStore();
    await tester.pumpWidget(app(_FakePlan(ZtPlan.free), store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'$2.99 a month'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.done.complete(ZtPurchaseOutcome.purchased);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
