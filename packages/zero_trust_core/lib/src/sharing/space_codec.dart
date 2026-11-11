import 'dart:convert';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import '../sync/item_sync_engine.dart';
import '../sync/local_item_store.dart';
import '../sync/sync_backend.dart';
import 'space_backend.dart';

/// Which items only a space's admins may write. Items whose id starts with
/// `zt.` belong to the core (the member list) and are always admin-only.
class SpacePolicy {
  const SpacePolicy({this.adminOnlyKinds = const {}});

  /// Item `kind`s only admins may create, change or delete (in Meds:
  /// children, medications and treatments; caregivers only log doses).
  final Set<String> adminOnlyKinds;

  bool isAdminOnly(String itemId, Map<String, Object?>? json) =>
      itemId.startsWith('zt.') ||
      (json != null && adminOnlyKinds.contains(json['kind']));
}

/// One person in a space's member list. Kept inside the space as an
/// encrypted item (`zt.member/<userId>`), written and signed by an admin, so
/// names and keys never reach the server.
class SpaceMember {
  const SpaceMember({
    required this.userId,
    required this.name,
    required this.identity,
    required this.role,
    this.everAdmin = false,
    this.removedAtEpoch,
  });

  factory SpaceMember.fromJson(Map<String, Object?> json) => SpaceMember(
        userId: json['userId'] as String,
        name: json['name'] as String? ?? '',
        identity: ZtPublicIdentity.fromJson(
            (json['identity'] as Map).cast<String, Object?>()),
        role: SpaceRole.parse(json['role'] as String? ?? 'member'),
        everAdmin: json['everAdmin'] as bool? ?? json['role'] == 'admin',
        removedAtEpoch: (json['removedAtEpoch'] as num?)?.toInt(),
      );

  static const kind = 'zt.member';
  static String itemIdFor(String userId) => 'zt.member/$userId';

  final String userId;
  final String name;
  final ZtPublicIdentity identity;
  final SpaceRole role;

  /// Has been an admin at some point: their admin-only items stay valid
  /// after a demotion. (The server stops their new admin writes.)
  final bool everAdmin;

  /// Removed from the space when the key moved to this epoch. Their rows
  /// sealed under it or later are never accepted. Kept rather than deleted,
  /// so what they wrote before stays verifiable.
  final int? removedAtEpoch;

  bool get removed => removedAtEpoch != null;
  bool get isAdmin => role == SpaceRole.admin && !removed;

  SpaceMember copyWith({
    String? name,
    SpaceRole? role,
    int? removedAtEpoch,
  }) {
    final r = role ?? this.role;
    return SpaceMember(
      userId: userId,
      name: name ?? this.name,
      identity: identity,
      role: r,
      everAdmin: everAdmin || r == SpaceRole.admin,
      removedAtEpoch: removedAtEpoch ?? this.removedAtEpoch,
    );
  }

  Map<String, Object?> toJson() => {
        'kind': kind,
        'userId': userId,
        'name': name,
        'identity': identity.toJson(),
        'role': role.name,
        'everAdmin': everAdmin || role == SpaceRole.admin,
        'removedAtEpoch': removedAtEpoch,
      };
}

/// Where trust in a space starts: the person whose invite this account
/// accepted (their identity fingerprint came in the invite link), or this
/// account itself for a space it created.
class SpaceAnchor {
  const SpaceAnchor({required this.userId, required this.fingerprint});

  factory SpaceAnchor.fromJson(Map<String, Object?> json) => SpaceAnchor(
        userId: json['userId'] as String,
        fingerprint: ZtBase64.decode(json['fingerprint'] as String),
      );

  final String userId;
  final Uint8List fingerprint;

  Map<String, Object?> toJson() =>
      {'userId': userId, 'fingerprint': ZtBase64.encode(fingerprint)};
}

/// The member list this device trusts, built from the anchor outward: the
/// anchor's own entry (its keys must match the fingerprint), then every
/// entry written by a trusted admin.
class SpaceRoster {
  SpaceRoster(this.anchor);

  final SpaceAnchor anchor;

  /// Who the server lists as admins right now. Only counts for members this
  /// device already trusts: it covers a member the server promoted when the
  /// last admin left or deleted their account, which no admin could sign.
  Set<String> serverAdmins = const {};

  final Map<String, SpaceMember> _members = {};
  final Map<String, DateTime> _versions = {};

  SpaceMember? operator [](String userId) => _members[userId];
  Iterable<SpaceMember> get all => _members.values;
  Iterable<SpaceMember> get current => all.where((m) => !m.removed);

  /// Adds or replaces an entry that has passed the checks, unless a newer
  /// version is already known.
  bool accept(SpaceMember member, DateTime version) {
    final known = _versions[member.userId];
    if (known != null && !version.isAfter(known)) return false;
    _members[member.userId] = member;
    _versions[member.userId] = version;
    return true;
  }

  /// Whether [author] could vouch for other members in a row sealed under
  /// [epoch]: an admin (now or before) who hadn't been removed by then.
  bool canVouch(String? author, int epoch) {
    final m = author == null ? null : _members[author];
    if (m == null || !mayAdminister(m)) return false;
    final removedAt = m.removedAtEpoch;
    return removedAt == null || epoch < removedAt;
  }

  /// An admin by the member list (now or before), or by the server now.
  bool mayAdminister(SpaceMember m) =>
      m.everAdmin ||
      m.role == SpaceRole.admin ||
      serverAdmins.contains(m.userId);
}

/// The space keys this device holds, by epoch, and which of them are
/// confirmed (wrapped and signed by a trusted admin) for sealing new items.
class SpaceKeyring {
  final Map<int, Uint8List> _keys = {};
  final Set<int> _verified = {};
  int currentEpoch = 1;

  Uint8List? operator [](int epoch) => _keys[epoch];
  Iterable<int> get epochs => _keys.keys;

  void put(int epoch, Uint8List key, {bool verified = false}) {
    _keys[epoch]?.fillRange(0, _keys[epoch]!.length, 0);
    _keys[epoch] = key;
    if (verified) _verified.add(epoch);
  }

  void markVerified(int epoch) => _verified.add(epoch);
  bool isVerified(int epoch) => _verified.contains(epoch);

  /// The epoch to seal new items under, or null while the current key isn't
  /// confirmed yet (a write then waits instead of using a key the server
  /// might have planted).
  int? get writeEpoch =>
      _keys.containsKey(currentEpoch) && _verified.contains(currentEpoch)
          ? currentEpoch
          : null;

  void clear() {
    for (final k in _keys.values) {
      k.fillRange(0, k.length, 0);
    }
    _keys.clear();
    _verified.clear();
  }
}

/// No confirmed key to seal with yet; the item stays on the device.
class SpaceKeyUnavailable implements Exception {
  const SpaceKeyUnavailable();
  @override
  String toString() => 'SpaceKeyUnavailable';
}

/// Seals and checks the items of one shared space:
/// - sealed under the space key of the current epoch, with the space, item
///   and epoch as AAD, so the server can't move a blob elsewhere;
/// - signed with the author's identity over the space, item, time, epoch,
///   admin flag and author, so nobody can forge or re-attribute a row;
/// - accepted only from authors in the trusted [roster], only from before
///   their removal, and admin-only rows only from (former) admins.
class SpaceItemCodec implements ItemCodec {
  SpaceItemCodec({
    required this.spaceId,
    required this.myUserId,
    required ZtIdentity identity,
    required this.keyring,
    required this.roster,
    this.policy = const SpacePolicy(),
  }) : _identity = identity;

  final String spaceId;
  final String myUserId;
  final SpaceKeyring keyring;
  final SpaceRoster roster;
  final SpacePolicy policy;
  final ZtIdentity _identity;

  bool _closed = false;

  @override
  void close() {
    _closed = true;
    keyring.clear();
  }

  @override
  Future<RemoteItem> seal(LocalItem item, String deviceId) async {
    final epoch = keyring.writeEpoch;
    final key = epoch == null ? null : keyring[epoch];
    if (epoch == null || key == null) throw const SpaceKeyUnavailable();
    final adminOnly = policy.isAdminOnly(item.itemId, item.json);
    final blob = item.deleted
        ? null
        : await SealedBox.seal(
            utf8.encode(jsonEncode(item.json)),
            key,
            aad: _aad(item.itemId, epoch),
          );
    final updatedAt = item.updatedAt.toUtc();
    return RemoteItem(
      itemId: item.itemId,
      updatedAt: updatedAt,
      deviceId: deviceId,
      dataBlob: blob,
      deleted: item.deleted,
      keyEpoch: epoch,
      adminOnly: adminOnly,
      authorId: myUserId,
      signature: await _identity.sign(_signedBytes(
        itemId: item.itemId,
        updatedAt: updatedAt,
        deleted: item.deleted,
        epoch: epoch,
        adminOnly: adminOnly,
        authorId: myUserId,
        blob: blob,
      )),
    );
  }

  @override
  Future<Map<String, Object?>?> open(RemoteItem remote) async {
    if (_closed) throw StateError('closed');
    final author = remote.authorId;
    final member = author == null ? null : roster[author];
    if (member == null) throw const FormatException('Unknown author');
    final json = await _verifyAndOpen(remote, member.identity);
    _checkAllowed(remote, member, json);
    return json;
  }

  void _checkAllowed(
      RemoteItem remote, SpaceMember member, Map<String, Object?>? json) {
    final epoch = remote.keyEpoch ?? 0;
    final removedAt = member.removedAtEpoch;
    if (removedAt != null && epoch >= removedAt) {
      throw const FormatException('Written after the author was removed');
    }
    final adminOnly = remote.adminOnly ||
        policy.isAdminOnly(remote.itemId, json) ||
        // A tombstone has no content: judge it by what it deletes.
        (json == null && remote.itemId.startsWith('zt.'));
    if (adminOnly && !roster.mayAdminister(member)) {
      throw const FormatException('Admin-only item from a non-admin');
    }
  }

  Future<Map<String, Object?>?> _verifyAndOpen(
      RemoteItem remote, ZtPublicIdentity author) async {
    final signature = remote.signature;
    final epoch = remote.keyEpoch;
    if (signature == null || epoch == null) {
      throw const FormatException('Unsigned row');
    }
    final ok = await Signing.verify(
      _signedBytes(
        itemId: remote.itemId,
        updatedAt: remote.updatedAt.toUtc(),
        deleted: remote.deleted,
        epoch: epoch,
        adminOnly: remote.adminOnly,
        authorId: remote.authorId!,
        blob: remote.dataBlob,
      ),
      signature: signature,
      publicKey: author.signPublic,
    );
    if (!ok) throw const FormatException('Bad signature');
    if (remote.deleted) return null;
    final blob = remote.dataBlob;
    final key = keyring[epoch];
    if (blob == null) throw const FormatException('Missing blob');
    if (key == null) throw const FormatException('No key for this epoch yet');
    final clear =
        await SealedBox.open(blob, key, aad: _aad(remote.itemId, epoch));
    return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }

  /// Learns member-list entries from [batch] before anything in it is
  /// opened: the anchor's own entry first, then entries written by members
  /// already trusted, until nothing more can be learned.
  @override
  Future<void> prepare(List<RemoteItem> batch) async {
    final pending = [
      for (final r in batch)
        if (r.itemId.startsWith('zt.member/') && !r.deleted) r,
    ];
    var progress = true;
    while (progress && pending.isNotEmpty) {
      progress = false;
      for (final row in [...pending]) {
        final learned = await _learn(row);
        if (learned != null) {
          pending.remove(row);
          if (learned) progress = true;
        }
      }
    }
  }

  /// Null: can't judge this row yet. False: judged, nothing new. True: the
  /// roster changed.
  Future<bool?> _learn(RemoteItem row) async {
    final author = row.authorId;
    if (author == null) return false;
    final subject = row.itemId.substring('zt.member/'.length);
    try {
      if (roster.canVouch(author, row.keyEpoch ?? 0)) {
        final voucher = roster[author]!;
        final json = await _verifyAndOpen(row, voucher.identity);
        if (json == null) return false;
        _checkAllowed(row, voucher, json);
        final member = SpaceMember.fromJson(json);
        if (member.userId != subject) return false;
        return roster.accept(member, row.updatedAt);
      }
      // The anchor's own entry, about itself, by itself: its keys must match
      // the fingerprint this device got from the invite link.
      if (author == roster.anchor.userId &&
          subject == author &&
          roster[author] == null) {
        final key = keyring[row.keyEpoch ?? 0];
        final blob = row.dataBlob;
        if (key == null || blob == null) return null;
        final clear = await SealedBox.open(blob, key,
            aad: _aad(row.itemId, row.keyEpoch!));
        final member = SpaceMember.fromJson(
            (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>());
        final fp = await member.identity.fingerprint();
        if (member.userId != author ||
            !_sameBytes(fp, roster.anchor.fingerprint)) {
          return false;
        }
        await _verifyAndOpen(row, member.identity);
        return roster.accept(member, row.updatedAt);
      }
    } on Object {
      return false;
    }
    return null;
  }

  List<int> _aad(String itemId, int epoch) =>
      utf8.encode('zt/space-item/v1|$spaceId|$itemId|$epoch');

  List<int> _signedBytes({
    required String itemId,
    required DateTime updatedAt,
    required bool deleted,
    required int epoch,
    required bool adminOnly,
    required String authorId,
    required Uint8List? blob,
  }) =>
      [
        ...utf8.encode('zt/space-sig/v1|$spaceId|$itemId|'
            '${updatedAt.microsecondsSinceEpoch}|$deleted|$epoch|$adminOnly|'
            '$authorId|'),
        ...?blob,
      ];
}

/// The context a space key is wrapped under: one space, one epoch, one
/// recipient.
String spaceKeyContext(String spaceId, int epoch, String userId) =>
    'zt/space-key/v1|$spaceId|$epoch|$userId';

/// What an admin signs when handing a space key to a member.
List<int> spaceKeySignedBytes(
        String spaceId, int epoch, String userId, List<int> wrapped) =>
    [
      ...utf8.encode('zt/space-key-sig/v1|$spaceId|$epoch|$userId|'),
      ...wrapped,
    ];

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
