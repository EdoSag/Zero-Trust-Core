import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_backend.dart';
import 'space_backend.dart';

/// [SpaceBackend] over the `core_v10_shared_spaces` tables and functions.
class SupabaseSpaceBackend implements SpaceBackend {
  SupabaseSpaceBackend([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  /// Runs [call], turning the database's `zt_*` errors into [SpaceRefused].
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      if (e.message == 'zt_storage_full') throw const StorageLimitExceeded();
      if (e.message == 'zt_item_too_large') {
        throw const StorageLimitExceeded(itemTooLarge: true);
      }
      if (e.message.startsWith('zt_')) {
        throw SpaceRefused(e.message, e.details?.toString());
      }
      rethrow;
    }
  }

  Future<Object?> _rpc(String fn, Map<String, Object?> params) =>
      _guard(() async => await _client.rpc(fn, params: params));

  @override
  Future<List<SpaceInfo>> spaces(String app) => _guard(() async {
        final rows = await _client
            .from('zt_space_members')
            .select(
                'role, zt_spaces!inner(id, app, key_epoch, rotation_needed)')
            .eq('user_id', _me)
            .eq('zt_spaces.app', app);
        return [
          for (final r in rows)
            if (r['zt_spaces'] case final Map<String, dynamic> s)
              SpaceInfo(
                id: s['id'] as String,
                app: s['app'] as String,
                keyEpoch: (s['key_epoch'] as num).toInt(),
                rotationNeeded: (s['rotation_needed'] as bool?) ?? false,
                myRole: SpaceRole.parse(r['role'] as String),
              ),
        ];
      });

  @override
  Future<List<SpaceMemberRow>> members(String spaceId) => _guard(() async {
        final rows = await _client
            .from('zt_space_members')
            .select('user_id, role, added_at')
            .eq('space_id', spaceId);
        return [
          for (final r in rows)
            SpaceMemberRow(
              userId: r['user_id'] as String,
              role: SpaceRole.parse(r['role'] as String),
              addedAt: DateTime.tryParse(r['added_at'] as String? ?? ''),
            ),
        ];
      });

  @override
  Future<List<SpaceKeyRow>> myKeys(String spaceId) => _guard(() async {
        final rows = await _client
            .from('zt_space_keys')
            .select('epoch, wrapped_key, wrapped_by, signature')
            .eq('space_id', spaceId)
            .eq('user_id', _me);
        return [
          for (final r in rows)
            SpaceKeyRow(
              epoch: (r['epoch'] as num).toInt(),
              wrappedKey: _fromBytea(r['wrapped_key'] as String)!,
              wrappedBy: r['wrapped_by'] as String?,
              signature: _fromBytea(r['signature'] as String)!,
            ),
        ];
      });

  @override
  Future<void> createSpace({
    required String spaceId,
    required String app,
    required Uint8List wrappedKey,
    required Uint8List keySignature,
  }) =>
      _rpc('zt_create_space', {
        'p_space': spaceId,
        'p_app': app,
        'p_wrapped_key': _toBytea(wrappedKey),
        'p_key_signature': _toBytea(keySignature),
      });

  @override
  Future<void> createInvite({
    required String inviteId,
    required String spaceId,
    required SpaceRole role,
    required Uint8List tokenHash,
    required Duration validFor,
  }) =>
      _rpc('zt_create_space_invite', {
        'p_invite': inviteId,
        'p_space': spaceId,
        'p_role': role.name,
        'p_token_hash': _toBytea(tokenHash),
        'p_valid_for': '${validFor.inSeconds} seconds',
      });

  @override
  Future<InviteAnswered> answerInvite({
    required String inviteId,
    required Uint8List token,
    required Uint8List answer,
  }) async {
    final res = await _rpc('zt_answer_space_invite', {
      'p_invite': inviteId,
      'p_token': _toBytea(token),
      'p_answer': _toBytea(answer),
    });
    final json = (res is String ? jsonDecode(res) : res) as Map;
    return InviteAnswered(
      spaceId: json['space_id'] as String,
      app: json['app'] as String,
      role: SpaceRole.parse(json['role'] as String),
      invitedBy: json['invited_by'] as String,
    );
  }

  @override
  Future<List<SpaceInviteRow>> invites(String spaceId) => _guard(() async {
        final rows = await _client
            .from('zt_space_invites')
            .select('id, space_id, role, status, expires_at, created_by, '
                'answered_by, answer')
            .eq('space_id', spaceId);
        return [
          for (final r in rows)
            SpaceInviteRow(
              id: r['id'] as String,
              spaceId: r['space_id'] as String,
              role: SpaceRole.parse(r['role'] as String),
              status: InviteStatus.values.byName(r['status'] as String),
              expiresAt: DateTime.parse(r['expires_at'] as String),
              createdBy: r['created_by'] as String?,
              answeredBy: r['answered_by'] as String?,
              answer: _fromBytea(r['answer'] as String?),
            ),
        ];
      });

  @override
  Future<void> confirmInvite(String inviteId, List<SpaceKeyGrant> grants) =>
      _rpc('zt_confirm_space_invite', {
        'p_invite': inviteId,
        'p_keys': [
          for (final g in grants)
            {
              'epoch': g.epoch,
              'wrapped_key': base64Encode(g.wrappedKey),
              'signature': base64Encode(g.signature),
            },
        ],
      });

  @override
  Future<void> revokeInvite(String inviteId) =>
      _rpc('zt_revoke_space_invite', {'p_invite': inviteId});

  static List<Map<String, Object?>> _grants(List<SpaceKeyGrant> grants) => [
        for (final g in grants)
          {
            'user_id': g.userId,
            'wrapped_key': base64Encode(g.wrappedKey),
            'signature': base64Encode(g.signature),
          },
      ];

  @override
  Future<void> rotateKey(
          String spaceId, int newEpoch, List<SpaceKeyGrant> grants) =>
      _rpc('zt_rotate_space_key', {
        'p_space': spaceId,
        'p_new_epoch': newEpoch,
        'p_keys': _grants(grants),
      });

  @override
  Future<void> removeMember(String spaceId, String userId, int newEpoch,
          List<SpaceKeyGrant> grants) =>
      _rpc('zt_remove_space_member', {
        'p_space': spaceId,
        'p_user': userId,
        'p_new_epoch': newEpoch,
        'p_keys': _grants(grants),
      });

  @override
  Future<void> leave(String spaceId) =>
      _rpc('zt_leave_space', {'p_space': spaceId});

  @override
  Future<void> setRole(String spaceId, String userId, SpaceRole role) => _rpc(
      'zt_set_space_role',
      {'p_space': spaceId, 'p_user': userId, 'p_role': role.name});

  @override
  Future<void> deleteSpace(String spaceId) =>
      _rpc('zt_delete_space', {'p_space': spaceId});

  @override
  SyncBackend items(String spaceId) => _SupabaseSpaceItems(_client, spaceId);

  @override
  Future<void> Function() watch(String app, void Function() onChange) {
    final me = _me;
    var channel = _client.channel('zt_spaces:$me:$app');
    for (final table in const [
      'zt_space_members',
      'zt_space_keys',
      'zt_spaces',
      'zt_space_invites',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => onChange(),
      );
    }
    channel.subscribe();
    return () async {
      await _client.removeChannel(channel);
    };
  }
}

class _SupabaseSpaceItems implements SyncBackend {
  _SupabaseSpaceItems(this._client, this._spaceId);
  final SupabaseClient _client;
  final String _spaceId;
  static const _table = 'zt_space_items';
  static const _pageSize = 500;
  static const _columns = 'item_id, data_blob, signature, device_id, '
      'updated_at, deleted, synced_at, key_epoch, author_id, admin_only';

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      SupabaseSpaceBackend._guard(() async {
        final out = <RemoteItem>[];
        String? afterAt = since?.toUtc().toIso8601String();
        String? afterId;
        while (true) {
          var query =
              _client.from(_table).select(_columns).eq('space_id', _spaceId);
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
          afterAt = DateTime.parse(rows.last['synced_at'] as String)
              .toUtc()
              .toIso8601String();
          afterId = rows.last['item_id'] as String;
        }
      });

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) =>
      SupabaseSpaceBackend._guard(() async {
        final ids = itemIds.toList();
        final out = <RemoteItem>[];
        for (var i = 0; i < ids.length; i += 100) {
          final rows = await _client
              .from(_table)
              .select(_columns)
              .eq('space_id', _spaceId)
              .inFilter('item_id', ids.sublist(i, min(i + 100, ids.length)));
          out.addAll(rows.map(_fromRow));
        }
        return out;
      });

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    if (items.isEmpty) return {};
    // The guard trigger skips stale and far-future writes; skipped rows are
    // missing from the result.
    final rows =
        await SupabaseSpaceBackend._guard(() => _client.from(_table).upsert([
              for (final item in items)
                {
                  'space_id': _spaceId,
                  'item_id': item.itemId,
                  'key_epoch': item.keyEpoch,
                  'data_blob':
                      item.dataBlob == null ? null : _toBytea(item.dataBlob!),
                  'signature': _toBytea(item.signature!),
                  'device_id': item.deviceId,
                  'admin_only': item.adminOnly,
                  'updated_at': item.updatedAt.toUtc().toIso8601String(),
                  'deleted': item.deleted,
                },
            ], onConflict: 'space_id,item_id').select('item_id'));
    return {for (final r in rows) r['item_id'] as String};
  }

  @override
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange) {
    final channel = _client
        .channel('zt_space_items:$_spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'space_id',
            value: _spaceId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
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
        keyEpoch: (row['key_epoch'] as num?)?.toInt(),
        authorId: row['author_id'] as String?,
        adminOnly: (row['admin_only'] as bool?) ?? false,
      );
}

String _toBytea(Uint8List bytes) =>
    '\\x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

Uint8List? _fromBytea(String? value) {
  if (value == null) return null;
  final hex = value.startsWith('\\x') ? value.substring(2) : value;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
