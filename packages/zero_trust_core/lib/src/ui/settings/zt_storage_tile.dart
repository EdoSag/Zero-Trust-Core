import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/zt_l10n.dart';
import '../../storage/zt_storage_usage.dart';

/// The shared "Storage: 2.4 MB of 50 MB used" row, with a bar. Shows nothing
/// while loading or when the server can't be reached. [ZtSettingsPage] shows
/// it when `showStorageUsage` is set.
class ZtStorageTile extends ConsumerWidget {
  const ZtStorageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(ztStorageUsageProvider).value;
    if (usage == null) return const SizedBox.shrink();
    final l10n = ZtL10n.of(context);
    final theme = Theme.of(context);
    final full = usage.fraction >= 1;
    return ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: Text(l10n.storage),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.storageUsed(
            formatBytes(usage.itemBytes),
            formatBytes(usage.maxItemBytes),
          )),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: usage.fraction,
            color: full ? theme.colorScheme.error : null,
            semanticsLabel: l10n.storage,
          ),
          if (usage.attachmentBytes > 0) ...[
            const SizedBox(height: 6),
            Text(l10n.storageAttachments(
              formatBytes(usage.attachmentBytes),
              formatBytes(usage.maxAttachmentBytes),
            )),
          ],
        ],
      ),
    );
  }
}
