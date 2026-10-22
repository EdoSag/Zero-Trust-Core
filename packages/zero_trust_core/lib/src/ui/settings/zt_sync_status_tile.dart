import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_providers.dart';
import '../../sync/sync_scheduler.dart';

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
      subtitle: rejected == 0
          ? null
          : Text(rejected == 1
              ? "1 item couldn't be read"
              : "$rejected items couldn't be read"),
      onTap: status.isSyncing
          ? null
          : () => ref.read(ztSyncControllerProvider.notifier).syncNow(),
    );
  }
}

/// The row's title for [status] at [now].
String syncStatusLabel(SyncStatus status, DateTime now) {
  if (status.isSyncing) return 'Syncing…';
  if (status.error != null) return "Couldn't sync. Tap to retry";
  final at = status.lastSyncedAt;
  if (at == null) return 'Not synced yet';
  final ago = now.difference(at);
  if (ago.inMinutes < 1) return 'Synced just now';
  if (ago.inHours < 1) return 'Synced ${ago.inMinutes} min ago';
  if (ago.inDays < 1) {
    return ago.inHours == 1
        ? 'Synced 1 hour ago'
        : 'Synced ${ago.inHours} hours ago';
  }
  return ago.inDays == 1 ? 'Synced yesterday' : 'Synced ${ago.inDays} days ago';
}
