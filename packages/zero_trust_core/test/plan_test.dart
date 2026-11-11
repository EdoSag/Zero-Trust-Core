import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

class _FakePlan implements PlanSource {
  _FakePlan(this.plan);
  final ZtPlan? plan;
  @override
  Future<ZtPlan?> fetch() async => plan;
}

void main() {
  test('plan parses the zt_my_plan JSON', () {
    final p = ZtPlan.fromJson({
      'plan': 'plus',
      'names': {'en': 'Plus', 'he': 'פלוס'},
      'features': ['drive'],
      'status': 'active',
      'source': 'google_play',
      'current_period_end': '2026-12-11T10:00:00+00:00',
    });
    expect(p.isFree, isFalse);
    expect(p.has('drive'), isTrue);
    expect(p.has('vpn'), isFalse);
    expect(p.status, ZtPlanStatus.active);
    expect(p.source, ZtPlanSource.googlePlay);
    expect(p.periodEnd, DateTime.utc(2026, 12, 11, 10));
    expect(p.nameFor('he'), 'פלוס');
    expect(p.nameFor('de'), 'Plus');
  });

  test('free plan JSON', () {
    final p = ZtPlan.fromJson({
      'plan': 'free',
      'names': {},
      'features': [],
      'status': null,
      'source': null,
      'current_period_end': null,
    });
    expect(p.isFree, isTrue);
    expect(p.nameFor('en'), isNull);
    expect(p.features, isEmpty);
    expect(p.periodEnd, isNull);
  });

  test('unknown values from a newer server are tolerated', () {
    final p = ZtPlan.fromJson({
      'plan': 'family',
      'status': 'something_new',
      'source': 'other_store',
    });
    expect(p.status, isNull);
    expect(p.source, isNull);
    expect(p.nameFor('en'), 'family');
  });

  Widget app(ZtPlan? plan, {VoidCallback? onTap, Locale? locale}) =>
      ProviderScope(
        overrides: [ztPlanSourceProvider.overrideWithValue(_FakePlan(plan))],
        child: MaterialApp(
          locale: locale,
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: ZtLanguages.delegates,
          theme: ZtTheme.light(),
          home: Scaffold(body: ZtPlanTile(onTap: onTap)),
        ),
      );

  testWidgets('free plan with a plans screen', (tester) async {
    var tapped = false;
    await tester.pumpWidget(app(ZtPlan.free, onTap: () => tapped = true));
    await tester.pumpAndSettle();
    expect(find.text('Plan: Free'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    await tester.tap(find.text('Plan: Free'));
    expect(tapped, isTrue);
  });

  testWidgets('free plan where the build may not sell: just the plan',
      (tester) async {
    await tester.pumpWidget(app(ZtPlan.free));
    await tester.pumpAndSettle();
    expect(find.text('Plan: Free'), findsOneWidget);
    expect(find.text('See plans'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('paid plan shows its renewal date', (tester) async {
    await tester.pumpWidget(app(ZtPlan(
      id: 'plus',
      names: const {'en': 'Plus'},
      status: ZtPlanStatus.active,
      periodEnd: DateTime(2026, 12, 11, 12),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Plan: Plus'), findsOneWidget);
    expect(find.text('Renews Dec 11, 2026'), findsOneWidget);
  });

  testWidgets('payment problem is shown', (tester) async {
    await tester.pumpWidget(app(const ZtPlan(
      id: 'plus',
      names: {'en': 'Plus'},
      status: ZtPlanStatus.grace,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Payment problem'), findsOneWidget);
  });

  testWidgets('Hebrew', (tester) async {
    await tester.pumpWidget(app(ZtPlan.free, locale: const Locale('he')));
    await tester.pumpAndSettle();
    expect(find.text('תוכנית: חינם'), findsOneWidget);
  });

  testWidgets('signed out: no row', (tester) async {
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });
}
