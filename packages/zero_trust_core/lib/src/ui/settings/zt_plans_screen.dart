import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../billing/zt_billing_store.dart';
import '../../billing/zt_plan.dart';
import '../../l10n/zt_l10n.dart';

/// Shows the account's plan and lets people buy or manage Plus through the
/// build's store ([ztBillingStoreProvider]). Open it from
/// `ZtSettingsPage(onOpenPlans: ...)`.
///
/// Without a store, or when the store has nothing for sale, it says Plus
/// can't be bought here yet. Prices always come from the store.
class ZtPlansScreen extends ConsumerStatefulWidget {
  const ZtPlansScreen({super.key, this.termsUrl, this.onOpenUrl});

  /// Shown under the fine print when [onOpenUrl] is set.
  final Uri? termsUrl;
  final void Function(Uri url)? onOpenUrl;

  @override
  ConsumerState<ZtPlansScreen> createState() => _ZtPlansScreenState();
}

class _ZtPlansScreenState extends ConsumerState<ZtPlansScreen> {
  Future<List<ZtStoreOffer>>? _offers;
  ZtBillingStore? _offersFrom;
  bool _busy = false;

  Future<List<ZtStoreOffer>> _offersOf(ZtBillingStore? store) {
    if (_offers == null || !identical(store, _offersFrom)) {
      _offersFrom = store;
      _offers = store == null ? Future.value(const []) : store.offers();
    }
    return _offers!;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(ZtBillingStore store, ZtStoreOffer offer) => _run(() async {
        final l10n = ZtL10n.of(context);
        final messenger = ScaffoldMessenger.of(context);
        ZtPurchaseOutcome outcome;
        try {
          outcome = await store.buy(offer);
        } catch (_) {
          outcome = ZtPurchaseOutcome.failed;
        }
        final message = switch (outcome) {
          ZtPurchaseOutcome.purchased => l10n.plansThanks,
          ZtPurchaseOutcome.pending => l10n.plansPending,
          ZtPurchaseOutcome.failed => l10n.plansFailed,
          ZtPurchaseOutcome.canceled => null,
        };
        if (outcome == ZtPurchaseOutcome.purchased) {
          ref.invalidate(ztPlanProvider);
        }
        if (message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      });

  @override
  Widget build(BuildContext context) {
    final l10n = ZtL10n.of(context);
    final theme = Theme.of(context);
    final store = ref.watch(ztBillingStoreProvider);
    final plan = ref.watch(ztPlanProvider).value;
    final language = Localizations.localeOf(context).languageCode;
    final planName = plan?.nameFor(language) ?? l10n.planFree;
    final paid = plan != null && !plan.isFree;

    final end = plan?.periodEnd;
    final date = end == null
        ? null
        : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
            .format(end.toLocal());
    final status = switch (plan?.status) {
      ZtPlanStatus.grace => l10n.planPaymentProblem,
      ZtPlanStatus.canceled when date != null => l10n.planEnds(date),
      ZtPlanStatus.active when date != null => l10n.planRenews(date),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.plansTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(l10n.planName(planName)),
              subtitle: status == null
                  ? null
                  : Text(status,
                      style: plan?.status == ZtPlanStatus.grace
                          ? TextStyle(color: theme.colorScheme.error)
                          : null),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.plansPlusName,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(l10n.plansPlusTagline,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  for (final line in [
                    l10n.plansPlusSynced,
                    l10n.plansPlusFiles,
                    l10n.plansPlusAllApps,
                    l10n.plansPlusSameEncryption,
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(line)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (paid)
                    _PaidActions(
                      plan: plan,
                      store: store,
                      busy: _busy,
                      onManage: (s) => _run(s.manage),
                    )
                  else
                    FutureBuilder<List<ZtStoreOffer>>(
                      future: _offersOf(store),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator()));
                        }
                        final offers = (snapshot.data ?? const [])
                            .where((o) => o.planId == 'plus')
                            .toList()
                          ..sort((a, b) =>
                              a.period.index.compareTo(b.period.index));
                        if (store == null || offers.isEmpty) {
                          return Text(l10n.plansNotAvailable,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final o in offers)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: o.period == ZtBillingPeriod.year
                                    ? FilledButton(
                                        onPressed:
                                            _busy ? null : () => _buy(store, o),
                                        child: Text(l10n.plansYearly(o.price)),
                                      )
                                    : OutlinedButton(
                                        onPressed:
                                            _busy ? null : () => _buy(store, o),
                                        child: Text(l10n.plansMonthly(o.price)),
                                      ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          if (store != null && !paid)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await store.restore();
                          ref.invalidate(ztPlanProvider);
                        }),
                child: Text(l10n.plansRestore),
              ),
            ),
          const SizedBox(height: 8),
          Text(l10n.plansFinePrint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (widget.termsUrl != null && widget.onOpenUrl != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => widget.onOpenUrl!(widget.termsUrl!),
                child: Text(l10n.termsOfUse),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaidActions extends StatelessWidget {
  const _PaidActions({
    required this.plan,
    required this.store,
    required this.busy,
    required this.onManage,
  });

  final ZtPlan plan;
  final ZtBillingStore? store;
  final bool busy;
  final void Function(ZtBillingStore store) onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = ZtL10n.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final name = plan.nameFor(language) ?? plan.id;
    final s = store;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(plan.source == ZtPlanSource.manual
            ? l10n.plansGranted(name)
            : l10n.plansYouHave(name)),
        // Manage only where it was bought: a Play subscription can't be
        // changed from the web checkout and the other way round.
        if (s != null && plan.source != ZtPlanSource.manual) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : () => onManage(s),
            child: Text(l10n.plansManage),
          ),
        ],
      ],
    );
  }
}
