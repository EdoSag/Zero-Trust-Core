import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/zt_app_config.dart';
import '../core_providers.dart';
import '../sync/sync_providers.dart';
import '../vault/vault_controller.dart';
import 'attachment_backend.dart';
import 'attachment_cache.dart';
import 'zt_attachments.dart';

final ztAttachmentBackendProvider =
    Provider<AttachmentBackend>((ref) => SupabaseAttachmentBackend());

/// Changes on every unlock and lock: each unlock holds a new key buffer, so
/// even a lock and unlock with nothing in between counts as a change. The
/// account service doesn't notify when the signed-in user changes, but
/// switching accounts always locks and unlocks again, so per-account
/// providers watch this and read the user id afresh.
final _unlockedProvider = Provider<Object?>((ref) => ref.watch(
    vaultControllerProvider
        .select((s) => s is VaultUnlocked ? s.appKey : null)));

/// Where the signed-in account's encrypted attachment files are kept on
/// this device, while the vault is unlocked. Tests override it with
/// [InMemoryAttachmentCache].
final ztAttachmentCacheProvider = FutureProvider<AttachmentCache>((ref) {
  if (ref.watch(_unlockedProvider) == null) throw const VaultIsLocked();
  final appId = ref.watch(ztAppConfigProvider.select((c) => c.appId));
  final userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  return FileAttachmentCache.forAccount(appId: appId, userId: userId);
});

/// Encrypted attachments for the signed-in account (see [ZtAttachments]),
/// while the vault is unlocked; rebuilt for whoever unlocks next. Waiting
/// uploads and deletes are retried after every successful sync.
final ztAttachmentsProvider = FutureProvider<ZtAttachments>((ref) async {
  if (ref.watch(_unlockedProvider) == null) throw const VaultIsLocked();
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
