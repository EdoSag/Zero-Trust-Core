import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import '../sync/item_sync_engine.dart';
import '../sync/local_item_store.dart';
import '../sync/sync_backend.dart';
import '../vault/vault_controller.dart';
import 'shared_spaces.dart';

/// Small notes every Zero-Trust app of one account can read and write
/// (`vault_items` app `suite`), sealed under [VaultUnlocked.suiteKey] and
/// signed with keys derived from it, like each app's own items. Only the
/// account itself can read or forge them.
///
/// Read and written straight on the server (no local copy): callers keep
/// what they need in their own store.
class ZtSuiteNotes implements SpacePrivateStore {
  ZtSuiteNotes._(this._backend, this._codec, this._deviceId);

  static Future<ZtSuiteNotes> open({
    required Uint8List suiteKey,
    required SyncBackend backend,
    required String deviceId,
  }) async {
    final key = Uint8List.fromList(suiteKey);
    try {
      final codec = AppItemCodec(
        appId: ztSuiteNotesApp,
        appKey: key,
        signingKeys: await KeyHierarchy.signingKeys(key),
      );
      return ZtSuiteNotes._(backend, codec, deviceId);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  final SyncBackend _backend;
  final AppItemCodec _codec;
  final String _deviceId;

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final rows = await _backend.fetch(ztSuiteNotesApp, {id});
    for (final row in rows) {
      if (row.itemId == id) return _codec.open(row);
    }
    return null;
  }

  @override
  Future<void> write(String id, Map<String, Object?> json) => _put(
      LocalItem(itemId: id, updatedAt: DateTime.now().toUtc(), json: json));

  @override
  Future<void> remove(String id) => _put(
      LocalItem(itemId: id, updatedAt: DateTime.now().toUtc(), deleted: true));

  Future<void> _put(LocalItem item) async {
    final row = await _codec.seal(item, _deviceId);
    await _backend.pushAll(ztSuiteNotesApp, [row]);
  }

  /// Zeroes the key. Further calls fail.
  void close() => _codec.close();
}
