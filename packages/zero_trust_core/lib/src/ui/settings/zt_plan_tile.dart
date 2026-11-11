import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../billing/zt_plan.dart';
import '../../l10n/zt_l10n.dart';

/// The shared "Plan: Free" row. Shows nothing while loading or when the
/// server can't be reached. [ZtSettingsPage] shows it when `showPlan` is
/// set.
///
/// [onTap] opens the app's plans screen. Apps pass it only where buying is
/// allowed (store builds use the store's own billing); without it the row
/// only shows the plan.
class ZtPlanTile extends ConsumerWidget {
  const ZtPlanTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(ztPlanProvider).value;
    if (plan == null) return const SizedBox.shrink();
    final l10n = ZtL10n.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final name = plan.nameFor(language) ?? l10n.planFree;
    final end = plan.periodEnd;
    // With the year: a yearly plan renews next year.
    final date = end == null
        ? null
        : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
            .format(end.toLocal());
    final subtitle = switch (plan.status) {
      ZtPlanStatus.grace => l10n.planPaymentProblem,
      ZtPlanStatus.canceled when date != null => l10n.planEnds(date),
      ZtPlanStatus.active when date != null => l10n.planRenews(date),
      _ => plan.isFree && onTap != null ? l10n.planSeePlans : null,
    };
    return ListTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: Text(l10n.planName(name)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: plan.status == ZtPlanStatus.grace
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
