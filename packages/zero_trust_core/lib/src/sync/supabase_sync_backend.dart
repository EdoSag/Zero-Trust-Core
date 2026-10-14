import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_backend.dart';

/// [SyncBackend] over the shared `vault_items` table (RLS: own rows only).
class SupabaseSyncBackend implements SyncBackend {
  SupabaseSyncBackend([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _table = 'vault_items';
  static const _pageSize = 500;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    final out = <RemoteItem>[];
    // Keyset cursor on (synced_at, item_id): rows sharing a timestamp (a
    // backfill, one transaction) page correctly however many there are.
    String? afterAt = since?.toUtc().toIso8601String();
    String? afterId;
    while (true) {
      var query = _client
          .from(_table)
          .select(
              'item_id, data_blob, signature, device_id, updated_at, deleted, synced_at')
          .eq('user_id', _userId)
          .eq('app', app);
      if (afterAt != null && afterId == null) {
        query = query.gt('synced_at', afterAt);
      } else if (afterAt != null) {
        query = query.or('synced_at.gt."$afterAt",'
            'and(synced_at.eq."$afterAt",item_id.gt."$afterId")');
      }
      final rows =
          await query.order('synced_at').order('item_id').limit(_pageSize);
      out.addAll(rows.map(_fromRow));
      if (rows.length < _pageSize) return out;
      // Normalised to `...Z` so no `+00:00` ends up in the filter string.
      afterAt = DateTime.parse(rows.last['synced_at'] as String)
          .toUtc()
          .toIso8601String();
      afterId = rows.last['item_id'] as String;
    }
  }

  @override
  Future<bool> push(String app, RemoteItem item) async {
    // The vault_items trigger silently skips a write older than the stored
    // row; it then returns no row, which is how a stale push is detected.
    final rows = await _client.from(_table).upsert({
      'user_id': _userId,
      'app': app,
      'item_id': item.itemId,
      'data_blob': item.dataBlob == null ? null : _toBytea(item.dataBlob!),
      'signature': item.signature == null ? null : _toBytea(item.signature!),
      'device_id': item.deviceId,
      'updated_at': item.updatedAt.toUtc().toIso8601String(),
      'deleted': item.deleted,
    }, onConflict: 'user_id,app,item_id').select('item_id');
    return rows.isNotEmpty;
  }

  @override
  Future<void> Function() subscribe(
    String app,
    void Function(RemoteItem) onChange,
  ) {
    final userId = _userId;
    final channel = _client
        .channel('vault_items:$userId:$app')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty || row['app'] != app) return;
            onChange(_fromRow(row));
          },
        )
        .subscribe();
    return () async {
      await _client.removeChannel(channel);
    };
  }

  static RemoteItem _fromRow(Map<String, dynamic> row) => RemoteItem(
        itemId: row['item_id'] as String,
        dataBlob: _fromBytea(row['data_blob'] as String?),
        signature: _fromBytea(row['signature'] as String?),
        deviceId: (row['device_id'] as String?) ?? '',
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deleted: (row['deleted'] as bool?) ?? false,
        syncedAt: row['synced_at'] == null
            ? null
            : DateTime.parse(row['synced_at'] as String),
      );

  static String _toBytea(Uint8List bytes) =>
      '\\x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  static Uint8List? _fromBytea(String? value) {
    if (value == null) return null;
    final hex = value.startsWith('\\x') ? value.substring(2) : value;
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}
