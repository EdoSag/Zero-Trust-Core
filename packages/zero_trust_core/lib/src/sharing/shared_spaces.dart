import 'dart:async';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import '../sync/item_sync_engine.dart';
import '../sync/local_item_store.dart';
import 'space_backend.dart';
import 'space_codec.dart';
import 'space_invite_link.dart';

/// Where this account keeps its own notes about spaces: which key each
/// space's trust starts from, and the tokens of invites it sent. These go in
/// the account's private, synced store (not in the space), so every device
/// of the account knows them and no other member does.
abstract interface class SpacePrivateStore {
  Future<Map<String, Object?>?> read(String id);
  Future<void> write(String id, Map<String, Object?> json);
  Future<void> remove(String id);
}

class InMemorySpacePrivateStore implements SpacePrivateStore {
  final Map<String, Map<String, Object?>> items = {};
  @override
  Future<Map<String, Object?>?> read(String id) async => items[id];
  @override
  Future<void> write(String id, Map<String, Object?> json) async =>
      items[id] = json;
  @override
  Future<void> remove(String id) async => items.remove(id);
}

/// This device can't vouch for the space: it has no anchor for it (the
/// invite was answered on a device whose notes haven't synced here yet).
class SpaceNotTrusted implements Exception {
  const SpaceNotTrusted(this.spaceId);
  final String spaceId;
  @override
  String toString() => 'SpaceNotTrusted($spaceId)';
}

/// Someone answered an invite and waits for an admin to let them in.
class PendingJoin {
  const PendingJoin({
    required this.inviteId,
    required this.spaceId,
    required this.userId,
    required this.name,
    required this.role,
    required this.identity,
    required this.verificationCode,
  });

  final String inviteId;
  final String spaceId;
  final String userId;

  /// The name they gave. Shown so the admin knows who it is; the
  /// [verificationCode] is what proves it.
  final String name;
  final SpaceRole role;
  final ZtPublicIdentity identity;

  /// Must match the code on the invitee's phone before confirming.
  final String verificationCode;
}

/// An invite this account answered; an admin still has to confirm it.
class JoinStarted {
  const JoinStarted({
    required this.spaceId,
    required this.inviterUserId,
    required this.verificationCode,
  });
  final String spaceId;
  final String inviterUserId;

  /// Compare with the code on the inviter's phone.
  final String verificationCode;
}

/// One open shared space: its local store, sync engine and trusted member
/// list. Save and delete items through it like through the app's own sync.
class SharedSpace {
  SharedSpace._({
    required this.id,
    required this.store,
    required this.engine,
    required this.codec,
    required this.myRole,
  });

  final String id;
  final LocalItemStore store;
  final ItemSyncEngine engine;
  final SpaceItemCodec codec;
  SpaceRole myRole;

  /// Set once this account is no longer a member (removed, or the space was
  /// deleted). The local copy has been wiped.
  bool gone = false;

  SpaceRoster get roster => codec.roster;
  int get keyEpoch => codec.keyring.currentEpoch;
  bool get isAdmin => myRole == SpaceRole.admin;

  /// Current members (removed ones excluded), from the encrypted list.
  List<SpaceMember> get members => roster.current.toList();

  /// Items under the policy's `ownedPrefixes` can be saved only in this
  /// account's own name.
  Future<void> save(String itemId, Map<String, Object?> json) {
    _checkOwner(itemId);
    return engine.save(itemId, json);
  }

  Future<void> delete(String itemId) {
    _checkOwner(itemId);
    return engine.delete(itemId);
  }

  void _checkOwner(String itemId) {
    final owner = codec.policy.ownerOf(itemId);
    if (owner != null && owner != codec.myUserId) {
      throw ArgumentError.value(itemId, 'itemId', 'belongs to another member');
    }
  }
}

/// Shared spaces for one app: create, invite (link and QR), answer, confirm
/// with a verification code, remove with key rotation, leave, delete, and
/// sync. Pure logic over a [SpaceBackend]; `sharing_providers.dart` wires it
/// to the vault, the local stores and Supabase.
class SharedSpaces {
  SharedSpaces({
    required this.app,
    required this.myUserId,
    required ZtIdentity identity,
    required this.backend,
    required this.privateStore,
    required this.openStore,
    required this.deviceId,
    this.deleteStore,
    this.policy = const SpacePolicy(),
    DateTime Function()? clock,
  })  : _identity = identity,
        _clock = clock;

  final String app;
  final String myUserId;
  final SpaceBackend backend;
  final SpacePrivateStore privateStore;
  final Future<LocalItemStore> Function(String spaceId) openStore;

  /// Removes a space's local store once this account has left it.
  final Future<void> Function(String spaceId)? deleteStore;
  final String deviceId;
  final SpacePolicy policy;
  final ZtIdentity _identity;
  final DateTime Function()? _clock;

  final Map<String, Future<SharedSpace>> _open = {};
  bool _closed = false;

  static String anchorId(String spaceId) => 'zt.space-anchor/$spaceId';
  static String inviteId(String inviteId) => 'zt.space-invite/$inviteId';

  Future<Uint8List> get _myFingerprint => _identity.public.fingerprint();

  /// Spaces of this app the account belongs to, as the server lists them.
  Future<List<SpaceInfo>> list() => backend.spaces(app);

  /// A new space with this account as its only admin. [myName] is how the
  /// other members will see this account.
  Future<SharedSpace> create({required String myName}) async {
    final spaceId = newUuid();
    final key = Kdf.randomBytes(32);
    final wrapped = await KeyWrap.wrap(
      key: key,
      recipient: _identity.public,
      context: spaceKeyContext(spaceId, 1, myUserId),
    );
    await backend.createSpace(
      spaceId: spaceId,
      app: app,
      wrappedKey: wrapped,
      keySignature: await _identity
          .sign(spaceKeySignedBytes(spaceId, 1, myUserId, wrapped)),
    );
    await privateStore.write(anchorId(spaceId), {
      'kind': 'zt.space_anchor',
      'spaceId': spaceId,
      ...SpaceAnchor(userId: myUserId, fingerprint: await _myFingerprint)
          .toJson(),
    });
    final space = await open(spaceId);
    space.codec.keyring.put(1, key, verified: true);
    final me = SpaceMember(
      userId: myUserId,
      name: myName,
      identity: _identity.public,
      role: SpaceRole.admin,
      everAdmin: true,
    );
    space.roster.accept(me, DateTime.now().toUtc());
    await space.save(SpaceMember.itemIdFor(myUserId), me.toJson());
    await sync(space);
    return space;
  }

  /// Opens a space this account belongs to (cached until [close]).
  Future<SharedSpace> open(String spaceId) {
    _checkOpen();
    return _open[spaceId] ??= () async {
      try {
        return await _openSpace(spaceId);
      } on Object {
        _open.remove(spaceId);
        rethrow;
      }
    }();
  }

  Future<SharedSpace> _openSpace(String spaceId) async {
    final anchorJson = await privateStore.read(anchorId(spaceId));
    if (anchorJson == null) throw SpaceNotTrusted(spaceId);
    final roster = SpaceRoster(SpaceAnchor.fromJson(anchorJson));
    final store = await openStore(spaceId);
    for (final item in await store.all()) {
      final json = item.json;
      if (item.deleted || json == null || json['kind'] != SpaceMember.kind) {
        continue;
      }
      roster.accept(SpaceMember.fromJson(json), item.updatedAt);
    }
    final codec = SpaceItemCodec(
      spaceId: spaceId,
      myUserId: myUserId,
      identity: _identity,
      keyring: SpaceKeyring(),
      roster: roster,
      policy: policy,
    );
    final engine = ItemSyncEngine.withCodec(
      appId: app,
      codec: codec,
      deviceId: deviceId,
      store: store,
      backend: backend.items(spaceId),
      clock: _clock,
    );
    return SharedSpace._(
      id: spaceId,
      store: store,
      engine: engine,
      codec: codec,
      myRole: roster[myUserId]?.role ?? SpaceRole.member,
    );
  }

  /// Brings [space] up to date: keys, member list, items, and (on an
  /// admin's device) a new key when someone has left.
  Future<SyncResult> sync(SharedSpace space) async {
    _checkOpen();
    final info = await _info(space.id);
    if (info == null) {
      await _forget(space);
      return const SyncResult();
    }
    space.myRole = info.myRole;
    if (info.rotationNeeded && space.isAdmin) {
      // Someone left: make the new key before anything waiting on this
      // device is pushed, so they can't read it. When this device doesn't
      // know every remaining member's key yet, it syncs first (below).
      await _refreshKeys(space, info);
      try {
        await _rotate(space, await backend.members(space.id));
        final after = (await _info(space.id))!;
        if (!after.rotationNeeded) return await _syncOnce(space, after);
      } on StateError {
        // falls through
      }
    }
    var result = await _syncOnce(space, info);
    if (info.rotationNeeded && space.isAdmin) {
      await _rotate(space, await backend.members(space.id));
      result = await _syncOnce(space, (await _info(space.id))!);
    }
    return result;
  }

  Future<SyncResult> _syncOnce(SharedSpace space, SpaceInfo info) async {
    space.roster.serverAdmins = {
      for (final m in await backend.members(space.id))
        if (m.role == SpaceRole.admin) m.userId,
    };
    await _refreshKeys(space, info);
    final before = _rosterVersion(space);
    SyncResult result;
    try {
      result = await space.engine.sync();
    } on SpaceRefused catch (e) {
      if (!e.keyStale) rethrow;
      // Someone rotated the key between our refresh and our push.
      await _refreshKeys(space, (await _info(space.id))!);
      result = await space.engine.sync();
    } on SpaceKeyUnavailable {
      // Edits made before the current key was confirmed: the pull just
      // brought the member list that confirms it.
      await _refreshKeys(space, info);
      result = await space.engine.sync();
    }
    if (_rosterVersion(space) != before || result.rejected.isNotEmpty) {
      // New members or keys became trusted: confirm keys, read what waited.
      await _refreshKeys(space, info);
      if (_rosterVersion(space) != before) result = await space.engine.sync();
    }
    return result;
  }

  String _rosterVersion(SharedSpace s) => [
        for (final m in s.roster.all)
          '${m.userId}:${m.role.name}:${m.removedAtEpoch}',
        ...s.codec.keyring.epochs
            .where(s.codec.keyring.isVerified)
            .map((e) => 'k$e'),
      ].join(',');

  Future<SpaceInfo?> _info(String spaceId) async {
    for (final s in await backend.spaces(app)) {
      if (s.id == spaceId) return s;
    }
    return null;
  }

  Future<void> _refreshKeys(SharedSpace space, SpaceInfo info) async {
    final ring = space.codec.keyring;
    ring.currentEpoch = info.keyEpoch;
    for (final row in await backend.myKeys(space.id)) {
      if (ring.isVerified(row.epoch)) continue;
      final Uint8List key;
      try {
        key = await KeyWrap.unwrap(
          wrapped: row.wrappedKey,
          identity: _identity,
          context: spaceKeyContext(space.id, row.epoch, myUserId),
        );
      } on Object {
        continue; // not for us, or damaged: never used
      }
      // Trust a key only when a trusted admin (or this account) signed the
      // very row it came from. A key cached from another row is replaced,
      // never promoted by this row's signature.
      final by = row.wrappedBy;
      final ZtPublicIdentity? signer = by == myUserId
          ? _identity.public
          : (by != null && space.roster.canVouch(by, row.epoch)
              ? space.roster[by]!.identity
              : null);
      final signed = signer != null &&
          await Signing.verify(
              spaceKeySignedBytes(
                  space.id, row.epoch, myUserId, row.wrappedKey),
              signature: row.signature,
              publicKey: signer.signPublic);
      if (signed) {
        ring.put(row.epoch, key, verified: true);
      } else {
        // Unconfirmed: the latest row's key may open rows (whose authors
        // sign them), never seal new ones. Replacing an earlier unconfirmed
        // key lets a real row recover from a planted one.
        ring.put(row.epoch, key);
      }
    }
  }

  /// A link (and QR code) inviting someone to [spaceId] as [role]. Only an
  /// admin can invite. Valid for [validFor] (up to 30 days), for one person.
  Future<SpaceInviteLink> invite(
    String spaceId, {
    SpaceRole role = SpaceRole.member,
    Duration validFor = const Duration(days: 7),
  }) async {
    final id = newUuid();
    final secret = InviteSecret.generate();
    await backend.createInvite(
      inviteId: id,
      spaceId: spaceId,
      role: role,
      tokenHash: await secret.hash(),
      validFor: validFor,
    );
    await privateStore.write(inviteId(id), {
      'kind': 'zt.space_invite',
      'spaceId': spaceId,
      'token': ZtBase64.encode(secret.token),
    });
    return SpaceInviteLink(
      app: app,
      inviteId: id,
      secret: secret,
      inviterUserId: myUserId,
      inviterFingerprint: await _myFingerprint,
    );
  }

  /// Answers an invite [link] with this account's public identity and
  /// [myName]. The returned code must match the one on the inviter's phone;
  /// the space appears in [list] once they confirm.
  Future<JoinStarted> answer(SpaceInviteLink link,
      {required String myName}) async {
    if (link.app != app) {
      throw FormatException('This invite is for another app (${link.app})');
    }
    final sealed = await link.secret.sealAnswer(link.inviteId, {
      'userId': myUserId,
      'name': myName,
      'identity': _identity.public.toJson(),
    });
    // The server gets a proof derived from the token, never the token
    // itself, which is what seals the answer.
    final proof = await link.secret.proof();
    final InviteAnswered res;
    try {
      res = await backend.answerInvite(
        inviteId: link.inviteId,
        proof: proof,
        answer: sealed,
      );
    } finally {
      proof.fillRange(0, proof.length, 0);
    }
    if (res.invitedBy != link.inviterUserId) {
      throw const FormatException('The invite does not match its link');
    }
    final code = await VerificationCode.compute(
      inviteId: link.inviteId,
      inviterFingerprint: link.inviterFingerprint,
      inviteeFingerprint: await _myFingerprint,
    );
    await privateStore.write(anchorId(res.spaceId), {
      'kind': 'zt.space_anchor',
      'spaceId': res.spaceId,
      'verificationCode': code,
      ...SpaceAnchor(
              userId: link.inviterUserId, fingerprint: link.inviterFingerprint)
          .toJson(),
    });
    return JoinStarted(
      spaceId: res.spaceId,
      inviterUserId: link.inviterUserId,
      verificationCode: code,
    );
  }

  /// The verification code of a space this account joined, to show again
  /// while it waits to be confirmed.
  Future<String?> joinCode(String spaceId) async =>
      (await privateStore.read(anchorId(spaceId)))?['verificationCode']
          as String?;

  /// People who answered this account's invites to [spaceId] and wait to be
  /// let in. Answers that don't open with the invite's token are left out.
  Future<List<PendingJoin>> pendingJoins(String spaceId) async {
    final out = <PendingJoin>[];
    final myFp = await _myFingerprint;
    for (final row in await backend.invites(spaceId)) {
      if (row.status != InviteStatus.answered || row.answer == null) continue;
      final note = await privateStore.read(inviteId(row.id));
      if (note == null) continue; // another admin's invite
      try {
        final secret = InviteSecret(ZtBase64.decode(note['token'] as String));
        final json = await secret.openAnswer(row.id, row.answer!);
        if (json['userId'] != row.answeredBy) continue;
        final identity = ZtPublicIdentity.fromJson(
            (json['identity'] as Map).cast<String, Object?>());
        out.add(PendingJoin(
          inviteId: row.id,
          spaceId: spaceId,
          userId: row.answeredBy!,
          name: (json['name'] as String?) ?? '',
          role: row.role,
          identity: identity,
          verificationCode: await VerificationCode.compute(
            inviteId: row.id,
            inviterFingerprint: myFp,
            inviteeFingerprint: await identity.fingerprint(),
          ),
        ));
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// Lets [join] in, after the admin compared the verification codes: adds
  /// them to the member list and hands them every key this device holds,
  /// so they see the space's history too.
  Future<void> confirm(PendingJoin join) async {
    final space = await open(join.spaceId);
    // Latest member list and key first (vouching below rewrites entries).
    await sync(space);
    await _refreshKeys(space, (await _info(space.id))!);
    final ring = space.codec.keyring;
    if (ring.writeEpoch == null) throw const SpaceKeyUnavailable();
    final grants = [
      for (final epoch in ring.epochs.where(ring.isVerified))
        await _grant(space.id, epoch, ring[epoch]!, join.userId, join.identity),
    ];
    // The newcomer trusts the space from this account outward (their link
    // names it), so this account vouches for every entry it knows: an entry
    // another admin wrote would otherwise stay unverifiable for them, and
    // so would everything that admin writes.
    for (final m in space.roster.all.toList()) {
      if (m.userId == join.userId) continue;
      await space.save(SpaceMember.itemIdFor(m.userId), m.toJson());
    }
    final member = SpaceMember(
      userId: join.userId,
      name: join.name,
      identity: join.identity,
      role: join.role,
      everAdmin: join.role == SpaceRole.admin,
    );
    final itemId = SpaceMember.itemIdFor(join.userId);
    await space.save(itemId, member.toJson());
    try {
      await backend.confirmInvite(join.inviteId, grants);
    } on Object {
      await space.delete(itemId);
      rethrow;
    }
    space.roster.accept(member, DateTime.now().toUtc());
    await privateStore.remove(inviteId(join.inviteId));
    await sync(space);
  }

  /// Turns down an answer (the codes didn't match) or withdraws an invite.
  Future<void> revokeInvite(String id) async {
    await backend.revokeInvite(id);
    await privateStore.remove(inviteId(id));
  }

  /// Removes [userId] from [spaceId] and moves everyone else to a new key in
  /// the same step, so they can't read anything written from now on.
  Future<void> remove(String spaceId, String userId) async {
    final space = await open(spaceId);
    await sync(space);
    final remaining = [
      for (final m in await backend.members(spaceId))
        if (m.userId != userId) m,
    ];
    final newEpoch = space.keyEpoch + 1;
    final key = Kdf.randomBytes(32);
    final grants = await _grantsFor(space, remaining, newEpoch, key);
    await backend.removeMember(spaceId, userId, newEpoch, grants);
    await _afterNewEpoch(space, newEpoch, key, departed: [userId]);
  }

  Future<void> _rotate(SharedSpace space, List<SpaceMemberRow> members) async {
    final newEpoch = space.keyEpoch + 1;
    final key = Kdf.randomBytes(32);
    final grants = await _grantsFor(space, members, newEpoch, key);
    final ids = {for (final m in members) m.userId};
    try {
      await backend.rotateKey(space.id, newEpoch, grants);
    } on SpaceRefused {
      return; // another admin rotated first; the next sync picks it up
    }
    await _afterNewEpoch(space, newEpoch, key, departed: [
      for (final m in space.roster.current)
        if (!ids.contains(m.userId)) m.userId,
    ]);
  }

  Future<List<SpaceKeyGrant>> _grantsFor(SharedSpace space,
      List<SpaceMemberRow> members, int epoch, Uint8List key) async {
    final grants = <SpaceKeyGrant>[];
    for (final m in members) {
      final entry = space.roster[m.userId];
      if (entry == null || entry.removed) {
        throw StateError('No trusted key for member ${m.userId} yet');
      }
      grants.add(await _grant(space.id, epoch, key, m.userId, entry.identity));
    }
    return grants;
  }

  Future<void> _afterNewEpoch(SharedSpace space, int epoch, Uint8List key,
      {required List<String> departed}) async {
    final ring = space.codec.keyring;
    ring.currentEpoch = epoch;
    ring.put(epoch, key, verified: true);
    for (final userId in departed) {
      final entry = space.roster[userId];
      if (entry == null) continue;
      final gone = entry.copyWith(removedAtEpoch: epoch);
      space.roster.accept(gone, DateTime.now().toUtc());
      await space.save(SpaceMember.itemIdFor(userId), gone.toJson());
    }
    await _syncOnce(space, (await _info(space.id))!);
  }

  Future<SpaceKeyGrant> _grant(String spaceId, int epoch, Uint8List key,
      String userId, ZtPublicIdentity to) async {
    final wrapped = await KeyWrap.wrap(
        key: key,
        recipient: to,
        context: spaceKeyContext(spaceId, epoch, userId));
    return SpaceKeyGrant(
      userId: userId,
      epoch: epoch,
      wrappedKey: wrapped,
      signature: await _identity
          .sign(spaceKeySignedBytes(spaceId, epoch, userId, wrapped)),
    );
  }

  /// Makes [userId] an admin or a plain member (admins only; the space
  /// always keeps at least one admin).
  Future<void> setRole(String spaceId, String userId, SpaceRole role) async {
    final space = await open(spaceId);
    final entry = space.roster[userId];
    if (entry == null) throw StateError('Unknown member');
    // The member list first, while this account is surely still an admin
    // (it may be demoting itself), then the server.
    final updated = entry.copyWith(role: role);
    final itemId = SpaceMember.itemIdFor(userId);
    space.roster.accept(updated, DateTime.now().toUtc());
    await space.save(itemId, updated.toJson());
    await sync(space);
    try {
      await backend.setRole(spaceId, userId, role);
    } on Object {
      final back = updated.copyWith(role: entry.role);
      space.roster.accept(back, DateTime.now().toUtc());
      await space.save(itemId, back.toJson());
      await sync(space);
      rethrow;
    }
    await sync(space);
  }

  /// Changes how a member is shown to everyone (admins only).
  Future<void> rename(String spaceId, String userId, String name) async {
    final space = await open(spaceId);
    final entry = space.roster[userId];
    if (entry == null) throw StateError('Unknown member');
    final updated = entry.copyWith(name: name);
    space.roster.accept(updated, DateTime.now().toUtc());
    await space.save(SpaceMember.itemIdFor(userId), updated.toJson());
    await sync(space);
  }

  /// Leaves [spaceId]. Its copy on this device is wiped; an admin's device
  /// makes a new key for the others.
  Future<void> leave(String spaceId) async {
    await backend.leave(spaceId);
    final space = await _open[spaceId];
    if (space != null) {
      await _forget(space);
    } else {
      await _wipe(spaceId);
    }
  }

  /// Deletes [spaceId] and everything in it, for every member (admins only).
  Future<void> deleteSpace(String spaceId) async {
    await backend.deleteSpace(spaceId);
    final space = await _open[spaceId];
    if (space != null) {
      await _forget(space);
    } else {
      await _wipe(spaceId);
    }
  }

  Future<void> _forget(SharedSpace space) async {
    space.gone = true;
    _open.remove(space.id);
    await space.engine.close();
    await _wipe(space.id);
  }

  Future<void> _wipe(String spaceId) async {
    await privateStore.remove(anchorId(spaceId));
    await deleteStore?.call(spaceId);
  }

  void _checkOpen() {
    if (_closed) throw StateError('SharedSpaces is closed');
  }

  /// Closes every open space (the vault locked). Keys are zeroed.
  Future<void> close() async {
    _closed = true;
    final open = [..._open.values];
    _open.clear();
    for (final f in open) {
      try {
        await (await f).engine.close();
      } on Object {
        // never opened
      }
    }
  }
}
