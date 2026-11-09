import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_providers.dart';
import '../../sync/sync_scheduler.dart';
import '../auth/zt_auth_messages.dart';

/// The shared sync row: "Synced 2 min ago", "Syncing…", or a failure with
/// tap to retry. [ZtSettingsPage] shows it when `showSyncStatus` is set.
class ZtSyncStatusTile extends ConsumerWidget {
  const ZtSyncStatusTile({super.key, this.now});

  /// For tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ztSyncControllerProvider);
    final theme = Theme.of(context);
    final rejected = status.rejected.length;
    return ListTile(
      leading: status.isSyncing
          ? const SizedBox.square(
              dimension: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(
              status.error != null
                  ? Icons.cloud_off_outlined
                  : Icons.cloud_done_outlined,
              color: status.error != null ? theme.colorScheme.error : null,
            ),
      title: Text(syncStatusLabel(status, (now ?? DateTime.now)())),
      subtitle: switch ((status.error, rejected)) {
        (final Object error, _) when !status.isSyncing =>
          Text(ztErrorMessage(error)),
        (_, 0) => null,
        _ => Text(ZtL10n.of(context).itemsUnreadable(rejected)),
      },
      onTap: status.isSyncing
          ? null
          : () => ref.read(ztSyncControllerProvider.notifier).syncNow(),
    );
  }
}

/// The row's title for [status] at [now].
String syncStatusLabel(SyncStatus status, DateTime now) {
  if (status.isSyncing) return ZtL10n.current.syncing;
  if (status.error != null) return ZtL10n.current.syncFailedRetry;
  final at = status.lastSyncedAt;
  if (at == null) return ZtL10n.current.notSyncedYet;
  final ago = now.difference(at);
  if (ago.inMinutes < 1) return ZtL10n.current.syncedJustNow;
  if (ago.inHours < 1) return ZtL10n.current.syncedMinutesAgo(ago.inMinutes);
  if (ago.inDays < 1) return ZtL10n.current.syncedHoursAgo(ago.inHours);
  return ZtL10n.current.syncedDaysAgo(ago.inDays);
}
