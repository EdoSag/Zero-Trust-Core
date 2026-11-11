import 'dart:typed_data';

import '../sync/sync_backend.dart';

/// A shared space as its members see it on the server.
class SpaceInfo {
  const SpaceInfo({
    required this.id,
    required this.app,
    required this.keyEpoch,
    required this.myRole,
    this.rotationNeeded = false,
  });

  final String id;
  final String app;

  /// The key epoch new items must be sealed under.
  final int keyEpoch;
  final SpaceRole myRole;

  /// Someone left or deleted their account: an admin should make a new key.
  final bool rotationNeeded;
}

enum SpaceRole {
  /// Manages members and admin-only items.
  admin,

  /// Reads everything, writes items that aren't admin-only.
  member;

  static SpaceRole parse(String value) =>
      value == 'admin' ? SpaceRole.admin : SpaceRole.member;
}

/// One row of the server's member list (routing metadata only; names and
/// keys are in the space's own encrypted member list).
class SpaceMemberRow {
  const SpaceMemberRow({
    required this.userId,
    required this.role,
    this.addedAt,
  });
  final String userId;
  final SpaceRole role;
  final DateTime? addedAt;
}

/// One of the caller's copies of a space key.
class SpaceKeyRow {
  const SpaceKeyRow({
    required this.epoch,
    required this.wrappedKey,
    required this.wrappedBy,
    required this.signature,
  });
  final int epoch;
  final Uint8List wrappedKey;
  final String? wrappedBy;
  final Uint8List signature;
}

/// A space key wrapped for one member, signed by the admin who wrapped it.
class SpaceKeyGrant {
  const SpaceKeyGrant({
    required this.userId,
    required this.epoch,
    required this.wrappedKey,
    required this.signature,
  });
  final String userId;
  final int epoch;
  final Uint8List wrappedKey;
  final Uint8List signature;
}

enum InviteStatus { open, answered, confirmed, revoked }

/// An invite as an admin sees it.
class SpaceInviteRow {
  const SpaceInviteRow({
    required this.id,
    required this.spaceId,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.createdBy,
    this.answeredBy,
    this.answer,
  });
  final String id;
  final String spaceId;
  final SpaceRole role;
  final InviteStatus status;
  final DateTime expiresAt;
  final String? createdBy;
  final String? answeredBy;

  /// The invitee's answer, sealed under the invite token.
  final Uint8List? answer;
}

/// What the server says after an invite is answered.
class InviteAnswered {
  const InviteAnswered({
    required this.spaceId,
    required this.app,
    required this.role,
    required this.invitedBy,
  });
  final String spaceId;
  final String app;
  final SpaceRole role;
  final String invitedBy;
}

/// The server refused a space change. [code] is the database error, such as
/// `zt_not_space_admin`, `zt_invite_invalid` or `zt_space_key_stale`.
class SpaceRefused implements Exception {
  const SpaceRefused(this.code, [this.detail]);
  final String code;
  final String? detail;

  bool get keyStale => code == 'zt_space_key_stale';

  @override
  String toString() =>
      'SpaceRefused($code${detail == null ? '' : ': $detail'})';
}

/// Server side of shared spaces: Supabase in production, in memory in tests.
/// Every call acts as the signed-in account; the server enforces who may do
/// what (see the `core_v10_shared_spaces` migration).
abstract interface class SpaceBackend {
  /// Spaces of [app] the caller belongs to.
  Future<List<SpaceInfo>> spaces(String app);

  Future<List<SpaceMemberRow>> members(String spaceId);

  /// The caller's own wrapped keys for [spaceId], every epoch they hold.
  Future<List<SpaceKeyRow>> myKeys(String spaceId);

  Future<void> createSpace({
    required String spaceId,
    required String app,
    required Uint8List wrappedKey,
    required Uint8List keySignature,
  });

  Future<void> createInvite({
    required String inviteId,
    required String spaceId,
    required SpaceRole role,
    required Uint8List tokenHash,
    required Duration validFor,
  });

  Future<InviteAnswered> answerInvite({
    required String inviteId,
    required Uint8List proof,
    required Uint8List answer,
  });

  /// Invites of [spaceId] (admins only).
  Future<List<SpaceInviteRow>> invites(String spaceId);

  /// Adds the invitee with [grants] (one per epoch, current included).
  Future<void> confirmInvite(String inviteId, List<SpaceKeyGrant> grants);

  Future<void> revokeInvite(String inviteId);

  /// A new epoch for every current member ([grants]: one per member).
  Future<void> rotateKey(
      String spaceId, int newEpoch, List<SpaceKeyGrant> grants);

  /// Removes [userId] and moves everyone else to [newEpoch] in one step.
  Future<void> removeMember(
      String spaceId, String userId, int newEpoch, List<SpaceKeyGrant> grants);

  Future<void> leave(String spaceId);

  Future<void> setRole(String spaceId, String userId, SpaceRole role);

  Future<void> deleteSpace(String spaceId);

  /// The space's items, as a [SyncBackend] for an `ItemSyncEngine`. Writes
  /// sealed under an old epoch throw [SpaceRefused] (`keyStale`).
  SyncBackend items(String spaceId);

  /// Calls [onChange] when the caller's spaces, memberships, keys or
  /// invites change (another device or member did something). Returns a
  /// cancel function.
  Future<void> Function() watch(String app, void Function() onChange);
}
