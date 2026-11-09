import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/zt_app_config.dart';
import '../core_providers.dart';
import '../sync/sync_providers.dart';
import 'attachment_backend.dart';
import 'attachment_cache.dart';
import 'zt_attachments.dart';

final ztAttachmentBackendProvider =
    Provider<AttachmentBackend>((ref) => SupabaseAttachmentBackend());

/// Where the signed-in account's encrypted attachment files are kept on
/// this device. Tests override it with [InMemoryAttachmentCache].
final ztAttachmentCacheProvider = FutureProvider<AttachmentCache>((ref) {
  final appId = ref.watch(ztAppConfigProvider.select((c) => c.appId));
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  return FileAttachmentCache.forAccount(appId: appId, userId: userId);
});

/// Encrypted attachments for the signed-in account (see [ZtAttachments]).
/// Waiting uploads and deletes are retried after every successful sync.
final ztAttachmentsProvider = FutureProvider<ZtAttachments>((ref) async {
  final appId = ref.watch(ztAppConfigProvider.select((c) => c.appId));
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final attachments = ZtAttachments(
    appId: appId,
    userId: userId,
    backend: ref.watch(ztAttachmentBackendProvider),
    cache: await ref.watch(ztAttachmentCacheProvider.future),
  );
  ref.listen(ztSyncControllerProvider.select((s) => s.lastSyncedAt),
      (previous, next) {
    if (next != null && next != previous) {
      attachments.flush().catchError((Object _) {});
    }
  });
  return attachments;
});
