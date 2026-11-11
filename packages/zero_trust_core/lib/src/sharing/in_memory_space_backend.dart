import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:cryptography/dart.dart';

import '../sync/sync_backend.dart';
import 'space_backend.dart';

/// The shared-space server in memory, with the same rules as the
/// `core_v10_shared_spaces` migration: membership through the functions
/// only, admin checks, invite tokens by hash, key epochs, admin-only items,
/// the last-writer-wins guard, promotion of a member when the last admin
/// leaves, and deletion of a space nobody is left in. For tests and
/// prototypes, in the core and in apps. One [InMemorySpaceServer] is the
/// server; each signed-in account talks to it through [backendFor].
class InMemorySpaceServer {
  final Map<String, _Space> _spaces = {};
  final Map<String, _Invite> _invites = {};
  final List<void Function()> _watchers = [];
  final List<void Function(String spaceId, RemoteItem row)> _itemWatchers = [];
  DateTime? _lastSync;

  /// Off: a misbehaving server that skips the admin-only check, so tests can
  /// show that members' devices still refuse such rows.
  bool enforceAdminOnly = true;

  InMemorySpaceBackend backendFor(String userId) =>
      InMemorySpaceBackend._(this, userId);

  /// Every stored row of [spaceId] (what an attacker with the database sees).
  List<RemoteItem> rowsOf(String spaceId) =>
      _spaces[spaceId]?.items.values.toList() ?? const [];

  /// Replaces a stored row as a compromised server could.
  void tamper(String spaceId, RemoteItem row) =>
      _spaces[spaceId]!.items[row.itemId] = row;

  /// Gives [userId] a key row nobody legitimate wrote (a planted key).
  void plantKey(String spaceId, String userId, SpaceKeyGrant grant,
          {String? wrappedBy}) =>
      _spaces[spaceId]!.keys[(grant.epoch, userId)] = SpaceKeyRow(
        epoch: grant.epoch,
        wrappedKey: grant.wrappedKey,
        wrappedBy: wrappedBy,
        signature: grant.signature,
      );

  /// Replaces an invite's answer as a compromised server could.
  void replaceAnswer(String inviteId, Uint8List answer) =>
      _invites[inviteId]!.answer = answer;

  bool hasSpace(String spaceId) => _spaces.containsKey(spaceId);

  /// What deleting an account does: removes it from every space.
  void deleteAccount(String userId) {
    for (final s in [..._spaces.values]) {
      if (s.members.containsKey(userId)) _removeMember(s, userId);
    }
    _notify();
  }

  DateTime _now() => clock.now().toUtc();

  /// Strictly increasing receive times, like `clock_timestamp()`.
  DateTime _syncTime() {
    final now = _now();
    final next = _lastSync == null || now.isAfter(_lastSync!)
        ? now
        : _lastSync!.add(const Duration(microseconds: 1));
    return _lastSync = next;
  }

  void _notify() {
    for (final w in [..._watchers]) {
      w();
    }
  }

  void _removeMember(_Space s, String userId) {
    s.members.remove(userId);
    s.keys.removeWhere((k, _) => k.$2 == userId);
    if (s.members.isEmpty) {
      _spaces.remove(s.id);
      _invites.removeWhere((_, i) => i.spaceId == s.id);
      return;
    }
    if (!s.members.values.any((m) => m.role == SpaceRole.admin)) {
      final first = s.members.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      s.members[first.first.userId] =
          _Member(first.first.userId, SpaceRole.admin, first.first.order);
    }
    s.rotationNeeded = true;
  }
}

class _Space {
  _Space(this.id, this.app);
  final String id;
  final String app;
  int keyEpoch = 1;
  bool rotationNeeded = false;
  int _order = 0;
  final Map<String, _Member> members = {};
  final Map<(int, String), SpaceKeyRow> keys = {};
  final Map<String, RemoteItem> items = {};
  int nextOrder() => _order++;
}

class _Member {
  _Member(this.userId, this.role, this.order);
  final String userId;
  final SpaceRole role;
  final int order;
}

class _Invite {
  _Invite(this.id, this.spaceId, this.createdBy, this.role, this.tokenHash,
      this.expiresAt);
  final String id;
  final String spaceId;
  final String createdBy;
  final SpaceRole role;
  final Uint8List tokenHash;
  final DateTime expiresAt;
  InviteStatus status = InviteStatus.open;
  String? answeredBy;
  Uint8List? answer;
}

/// One account's view of an [InMemorySpaceServer].
class InMemorySpaceBackend implements SpaceBackend {
  InMemorySpaceBackend._(this._server, this.userId);
  final InMemorySpaceServer _server;
  final String userId;

  _Space _space(String id) =>
      _server._spaces[id] ?? (throw const SpaceRefused('zt_not_space_admin'));

  _Space _asMember(String id) {
    final s = _space(id);
    if (!s.members.containsKey(userId)) {
      throw const SpaceRefused('zt_not_space_member');
    }
    return s;
  }

  _Space _asAdmin(String id) {
    final s = _server._spaces[id];
    if (s == null || s.members[userId]?.role != SpaceRole.admin) {
      throw const SpaceRefused('zt_not_space_admin');
    }
    return s;
  }

  @override
  Future<List<SpaceInfo>> spaces(String app) async => [
        for (final s in _server._spaces.values)
          if (s.app == app && s.members.containsKey(userId))
            SpaceInfo(
              id: s.id,
              app: s.app,
              keyEpoch: s.keyEpoch,
              myRole: s.members[userId]!.role,
              rotationNeeded: s.rotationNeeded,
            ),
      ];

  @override
  Future<List<SpaceMemberRow>> members(String spaceId) async => [
        for (final m in _asMember(spaceId).members.values)
          SpaceMemberRow(userId: m.userId, role: m.role),
      ];

  @override
  Future<List<SpaceKeyRow>> myKeys(String spaceId) async {
    final s = _server._spaces[spaceId];
    if (s == null) return const [];
    return [
      for (final e in s.keys.entries)
        if (e.key.$2 == userId) e.value,
    ];
  }

  @override
  Future<void> createSpace({
    required String spaceId,
    required String app,
    required Uint8List wrappedKey,
    required Uint8List keySignature,
  }) async {
    final s = _Space(spaceId, app);
    s.members[userId] = _Member(userId, SpaceRole.admin, s.nextOrder());
    s.keys[(1, userId)] = SpaceKeyRow(
        epoch: 1,
        wrappedKey: wrappedKey,
        wrappedBy: userId,
        signature: keySignature);
    _server._spaces[spaceId] = s;
    _server._notify();
  }

  @override
  Future<void> createInvite({
    required String inviteId,
    required String spaceId,
    required SpaceRole role,
    required Uint8List tokenHash,
    required Duration validFor,
  }) async {
    _asAdmin(spaceId);
    if (validFor > const Duration(days: 30)) {
      throw const SpaceRefused('zt_invite_invalid');
    }
    _server._invites[inviteId] = _Invite(inviteId, spaceId, userId, role,
        tokenHash, _server._now().add(validFor));
  }

  @override
  Future<InviteAnswered> answerInvite({
    required String inviteId,
    required Uint8List proof,
    required Uint8List answer,
  }) async {
    final inv = _server._invites[inviteId];
    final hash = (await const DartSha256().hash(proof)).bytes;
    if (inv == null ||
        !_same(hash, inv.tokenHash) ||
        inv.status != InviteStatus.open ||
        !inv.expiresAt.isAfter(_server._now())) {
      throw const SpaceRefused('zt_invite_invalid');
    }
    final s = _space(inv.spaceId);
    if (s.members.containsKey(userId)) {
      throw const SpaceRefused('zt_invite_invalid', 'already a member');
    }
    inv
      ..status = InviteStatus.answered
      ..answeredBy = userId
      ..answer = Uint8List.fromList(answer);
    _server._notify();
    return InviteAnswered(
        spaceId: s.id, app: s.app, role: inv.role, invitedBy: inv.createdBy);
  }

  @override
  Future<List<SpaceInviteRow>> invites(String spaceId) async {
    final admin =
        _server._spaces[spaceId]?.members[userId]?.role == SpaceRole.admin;
    return [
      for (final i in _server._invites.values)
        if (i.spaceId == spaceId && (admin || i.answeredBy == userId))
          SpaceInviteRow(
            id: i.id,
            spaceId: i.spaceId,
            role: i.role,
            status: i.status,
            expiresAt: i.expiresAt,
            createdBy: i.createdBy,
            answeredBy: i.answeredBy,
            answer: i.answer,
          ),
    ];
  }

  @override
  Future<void> confirmInvite(
      String inviteId, List<SpaceKeyGrant> grants) async {
    final inv = _server._invites[inviteId];
    if (inv == null) throw const SpaceRefused('zt_invite_invalid');
    final s = _asAdmin(inv.spaceId);
    if (inv.status != InviteStatus.answered) {
      throw const SpaceRefused('zt_invite_invalid');
    }
    if (!grants.any((g) => g.epoch == s.keyEpoch) ||
        grants.any((g) => g.epoch < 1 || g.epoch > s.keyEpoch)) {
      throw const SpaceRefused('zt_space_keys_mismatch');
    }
    final who = inv.answeredBy!;
    s.members[who] = _Member(who, inv.role, s.nextOrder());
    for (final g in grants) {
      s.keys[(g.epoch, who)] = SpaceKeyRow(
          epoch: g.epoch,
          wrappedKey: g.wrappedKey,
          wrappedBy: userId,
          signature: g.signature);
    }
    inv.status = InviteStatus.confirmed;
    _server._notify();
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    final inv = _server._invites[inviteId];
    if (inv == null) throw const SpaceRefused('zt_invite_invalid');
    _asAdmin(inv.spaceId);
    if (inv.status == InviteStatus.open ||
        inv.status == InviteStatus.answered) {
      inv.status = InviteStatus.revoked;
    }
  }

  void _newEpoch(_Space s, int newEpoch, List<SpaceKeyGrant> grants) {
    if (newEpoch != s.keyEpoch + 1) {
      throw const SpaceRefused('zt_space_keys_mismatch');
    }
    final ids = {for (final g in grants) g.userId};
    if (grants.length != s.members.length ||
        !s.members.keys.every(ids.contains)) {
      throw const SpaceRefused('zt_space_keys_mismatch');
    }
    for (final g in grants) {
      s.keys[(newEpoch, g.userId)] = SpaceKeyRow(
          epoch: newEpoch,
          wrappedKey: g.wrappedKey,
          wrappedBy: userId,
          signature: g.signature);
    }
    s.keyEpoch = newEpoch;
    s.rotationNeeded = false;
  }

  @override
  Future<void> rotateKey(
      String spaceId, int newEpoch, List<SpaceKeyGrant> grants) async {
    _newEpoch(_asAdmin(spaceId), newEpoch, grants);
    _server._notify();
  }

  @override
  Future<void> removeMember(String spaceId, String userId, int newEpoch,
      List<SpaceKeyGrant> grants) async {
    final s = _asAdmin(spaceId);
    if (userId == this.userId) throw const SpaceRefused('zt_last_admin');
    if (!s.members.containsKey(userId)) {
      throw const SpaceRefused('zt_space_keys_mismatch');
    }
    // Checked before removing, like the single transaction on the server.
    final remaining = {...s.members.keys}..remove(userId);
    final ids = {for (final g in grants) g.userId};
    if (newEpoch != s.keyEpoch + 1 ||
        grants.length != remaining.length ||
        !remaining.every(ids.contains)) {
      throw const SpaceRefused('zt_space_keys_mismatch');
    }
    _server._removeMember(s, userId);
    _newEpoch(s, newEpoch, grants);
    _server._notify();
  }

  @override
  Future<void> leave(String spaceId) async {
    final s = _server._spaces[spaceId];
    if (s != null && s.members.containsKey(userId)) {
      _server._removeMember(s, userId);
    }
    _server._notify();
  }

  @override
  Future<void> setRole(String spaceId, String userId, SpaceRole role) async {
    final s = _asAdmin(spaceId);
    final m = s.members[userId];
    if (m == null) throw const SpaceRefused('zt_space_keys_mismatch');
    final admins = s.members.values
        .where((x) => x.role == SpaceRole.admin && x.userId != userId)
        .length;
    if (role != SpaceRole.admin && admins == 0) {
      throw const SpaceRefused('zt_last_admin');
    }
    s.members[userId] = _Member(userId, role, m.order);
    _server._notify();
  }

  @override
  Future<void> deleteSpace(String spaceId) async {
    _asAdmin(spaceId);
    _server._spaces.remove(spaceId);
    _server._invites.removeWhere((_, i) => i.spaceId == spaceId);
    _server._notify();
  }

  @override
  SyncBackend items(String spaceId) => _SpaceItems(this, spaceId);

  @override
  Future<void> Function() watch(String app, void Function() onChange) {
    _server._watchers.add(onChange);
    return () async => _server._watchers.remove(onChange);
  }
}

class _SpaceItems implements SyncBackend {
  _SpaceItems(this._b, this._spaceId);
  final InMemorySpaceBackend _b;
  final String _spaceId;

  InMemorySpaceServer get _server => _b._server;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) async {
    final s = _b._asMember(_spaceId);
    return s.items.values
        .where((r) => since == null || r.syncedAt!.isAfter(since))
        .toList()
      ..sort((a, b) => a.syncedAt!.compareTo(b.syncedAt!));
  }

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) async {
    final s = _b._asMember(_spaceId);
    return [
      for (final id in itemIds)
        if (s.items[id] case final row?) row,
    ];
  }

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    final s = _b._asMember(_spaceId);
    final admin = s.members[_b.userId]!.role == SpaceRole.admin;
    // Checked first: a refusal rolls back the whole request.
    for (final item in items) {
      if (item.keyEpoch != s.keyEpoch) {
        throw const SpaceRefused('zt_space_key_stale');
      }
      final old = s.items[item.itemId];
      if (_server.enforceAdminOnly &&
          !admin &&
          (item.adminOnly || (old?.adminOnly ?? false))) {
        throw const SpaceRefused('zt_space_admin_only');
      }
    }
    final accepted = <String>{};
    for (final item in items) {
      final old = s.items[item.itemId];
      if (old != null && item.updatedAt.isBefore(old.updatedAt)) continue;
      final row = RemoteItem(
        itemId: item.itemId,
        updatedAt: item.updatedAt,
        deviceId: item.deviceId,
        dataBlob: item.dataBlob,
        signature: item.signature,
        deleted: item.deleted,
        keyEpoch: item.keyEpoch,
        adminOnly: item.adminOnly,
        authorId: _b.userId,
        syncedAt: _server._syncTime(),
      );
      s.items[item.itemId] = row;
      accepted.add(item.itemId);
      for (final w in [..._server._itemWatchers]) {
        w(_spaceId, row);
      }
    }
    return accepted;
  }

  @override
  Future<void> Function() subscribe(
      String app, void Function(RemoteItem) onChange) {
    void listener(String spaceId, RemoteItem row) {
      if (spaceId == _spaceId &&
          (_server._spaces[_spaceId]?.members.containsKey(_b.userId) ??
              false)) {
        onChange(row);
      }
    }

    _server._itemWatchers.add(listener);
    return () async => _server._itemWatchers.remove(listener);
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
