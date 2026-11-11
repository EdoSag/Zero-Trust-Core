import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// People waiting to join the spaces this account is an admin of. Needs
/// the internet; empty while offline. Invalidate it to check again.
final ztPendingJoinsProvider = FutureProvider<List<PendingJoin>>((ref) async {
  final state = ref.watch(ztSpacesProvider);
  final controller = ref.read(ztSpacesProvider.notifier);
  final out = <PendingJoin>[];
  for (final entry in state.entries) {
    if (entry.info.myRole != SpaceRole.admin) continue;
    try {
      out.addAll(await controller.pendingJoins(entry.info.id));
    } on Object {
      // Offline or not allowed: nothing to show for this space.
    }
  }
  return out;
});
