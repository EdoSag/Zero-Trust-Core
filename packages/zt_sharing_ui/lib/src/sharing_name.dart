import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// The name this account shows to the people it shares with, kept in the
/// app's own encrypted, synced store (item [itemId]), so every device of
/// the account uses the same one. Apps that list every item of their store
/// should skip items whose `kind` is [kind].
class ZtSharingName {
  ZtSharingName(this._ref);
  final Ref _ref;

  static const itemId = 'zt.sharing-name';
  static const kind = 'zt.sharing_name';

  Future<String> read() async {
    final store = await _ref.read(ztLocalStoreProvider.future);
    final item = await store.get(itemId);
    if (item == null || item.deleted) return '';
    return (item.json?['name'] as String?) ?? '';
  }

  Future<void> save(String name) async {
    if (name == await read()) return;
    await _ref
        .read(ztSyncControllerProvider.notifier)
        .save(itemId, {'kind': kind, 'name': name});
  }
}

final ztSharingNameProvider = Provider<ZtSharingName>(ZtSharingName.new);
