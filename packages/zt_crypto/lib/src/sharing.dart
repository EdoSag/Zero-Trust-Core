import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'kdf.dart';
import 'sealed_box.dart';
import 'signing.dart';
import 'zt_base64.dart';

/// The public half of a user's sharing identity: what other people need to
/// send them a key ([dhPublic], X25519) and to check what they wrote
/// ([signPublic], Ed25519).
class ZtPublicIdentity {
  ZtPublicIdentity({required List<int> dhPublic, required List<int> signPublic})
      : dhPublic = Uint8List.fromList(dhPublic),
        signPublic = Uint8List.fromList(signPublic) {
    if (this.dhPublic.length != 32 || this.signPublic.length != 32) {
      throw ArgumentError('Identity keys must be 32 bytes each');
    }
  }

  factory ZtPublicIdentity.fromJson(Map<String, Object?> json) =>
      ZtPublicIdentity(
        dhPublic: ZtBase64.decode(json['dh'] as String),
        signPublic: ZtBase64.decode(json['sign'] as String),
      );

  final Uint8List dhPublic;
  final Uint8List signPublic;

  Map<String, Object?> toJson() => {
        'dh': ZtBase64.encode(dhPublic),
        'sign': ZtBase64.encode(signPublic),
      };

  /// SHA-256 over both keys. Goes into invite links and verification codes,
  /// so a swapped key shows up as a different code.
  Future<Uint8List> fingerprint() async =>
      Uint8List.fromList((await _sha256.hash([
        ...utf8.encode('zt/identity-fp/v1|'),
        ...dhPublic,
        ...signPublic
      ]))
          .bytes);

  @override
  bool operator ==(Object other) =>
      other is ZtPublicIdentity &&
      _same(other.dhPublic, dhPublic) &&
      _same(other.signPublic, signPublic);

  @override
  int get hashCode => Object.hashAll([...dhPublic, ...signPublic]);
}

/// A user's sharing identity: an X25519 pair for receiving keys and an
/// Ed25519 pair for signing shared data.
///
/// Derived from the account DEK, so every device and every app of the same
/// account has the same identity without storing anything new, it survives
/// password changes and recoveries (the DEK never changes), and nothing
/// about it is kept on the server.
class ZtIdentity {
  ZtIdentity._(this._dhPrivate, this.public, this.signing);

  static const String _dhInfo = 'zt/identity/dh/v1';
  static const String _signInfo = 'zt/identity/sign/v1';

  /// Derives the account's identity from its [dek]. [dek] is not changed.
  static Future<ZtIdentity> fromDek(List<int> dek) async {
    final dhSeed = await Kdf.hkdf(dek, _dhInfo);
    final signSeed = await Kdf.hkdf(dek, _signInfo);
    try {
      final dh = await _x25519.newKeyPairFromSeed(dhSeed);
      final dhPublic = (await dh.extractPublicKey()).bytes;
      final dhPrivate = Uint8List.fromList(await dh.extractPrivateKeyBytes());
      final signing = await Signing.fromSeed(signSeed);
      return ZtIdentity._(
        dhPrivate,
        ZtPublicIdentity(
            dhPublic: dhPublic, signPublic: signing.publicKeyBytes),
        signing,
      );
    } finally {
      dhSeed.fillRange(0, dhSeed.length, 0);
      signSeed.fillRange(0, signSeed.length, 0);
    }
  }

  final Uint8List _dhPrivate;
  final ZtPublicIdentity public;
  final Ed25519KeyMaterial signing;

  Future<Uint8List> sign(List<int> message) => Signing.sign(message, signing);

  /// Zeroes the private keys. The identity can't be used afterwards.
  void destroy() {
    _dhPrivate.fillRange(0, _dhPrivate.length, 0);
    signing.privateKeyBytes.fillRange(0, signing.privateKeyBytes.length, 0);
  }

  Future<List<int>> _sharedSecret(List<int> peerDhPublic) async {
    final pair = SimpleKeyPairData(
      _dhPrivate,
      publicKey: SimplePublicKey(public.dhPublic, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final secret = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(peerDhPublic, type: KeyPairType.x25519),
    );
    return secret.extractBytes();
  }
}

/// Hands a symmetric key (a shared space's key) to one person: X25519 with a
/// fresh ephemeral key, HKDF, then an AES-256-GCM sealed box bound to
/// [context]. Only the holder of the recipient's identity can open it; the
/// server only relays the bytes.
///
/// Wire format: `ephemeralPublic(32) || sealedBox`.
abstract final class KeyWrap {
  static const String _info = 'zt/key-wrap/v1';

  static Future<Uint8List> wrap({
    required List<int> key,
    required ZtPublicIdentity recipient,
    required String context,
  }) async {
    final eph = await _x25519.newKeyPair();
    final ephPublic = (await eph.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey:
          SimplePublicKey(recipient.dhPublic, type: KeyPairType.x25519),
    );
    final kek = await Kdf.hkdf(await shared.extractBytes(), _info,
        salt: [...ephPublic, ...recipient.dhPublic]);
    try {
      final box = await SealedBox.seal(key, kek, aad: _aad(context));
      return Uint8List.fromList([...ephPublic, ...box]);
    } finally {
      kek.fillRange(0, kek.length, 0);
    }
  }

  /// Throws [SecretBoxAuthenticationError] when [wrapped] wasn't made for
  /// [identity] and [context], or was changed.
  static Future<Uint8List> unwrap({
    required List<int> wrapped,
    required ZtIdentity identity,
    required String context,
  }) async {
    if (wrapped.length < 32 + 12 + 16) {
      throw const FormatException('Wrapped key too short');
    }
    final ephPublic = wrapped.sublist(0, 32);
    final shared = await identity._sharedSecret(ephPublic);
    final kek = await Kdf.hkdf(shared, _info,
        salt: [...ephPublic, ...identity.public.dhPublic]);
    try {
      return await SealedBox.open(wrapped.sublist(32), kek, aad: _aad(context));
    } finally {
      kek.fillRange(0, kek.length, 0);
    }
  }

  static List<int> _aad(String context) =>
      utf8.encode('zt/key-wrap/v1|$context');
}

/// The secret half of an invite: a random token that travels only inside the
/// invite link or QR code (never to the server, which stores its hash).
/// Whoever holds it can answer the invite, and the answer is sealed under
/// it, so the server can neither read nor swap the invitee's keys.
class InviteSecret {
  InviteSecret(List<int> token) : token = Uint8List.fromList(token) {
    if (this.token.length != 32) throw ArgumentError('Token must be 32 bytes');
  }

  factory InviteSecret.generate() => InviteSecret(Kdf.randomBytes(32));

  final Uint8List token;

  /// What the invitee sends the server to show they hold the link. Derived
  /// from the token one way, so the server (which sees it) still can't
  /// derive the key that seals the answer, read the answer or forge one.
  Future<Uint8List> proof() => Kdf.hkdf(token, 'zt/invite-proof/v1');

  /// What the server keeps, to check an answer's [proof].
  Future<Uint8List> hash() async {
    final p = await proof();
    try {
      return Uint8List.fromList((await _sha256.hash(p)).bytes);
    } finally {
      p.fillRange(0, p.length, 0);
    }
  }

  /// Seals the invitee's answer (their public identity and display name).
  Future<Uint8List> sealAnswer(
      String inviteId, Map<String, Object?> answer) async {
    final key = await Kdf.hkdf(token, 'zt/invite-answer/v1');
    try {
      return await SealedBox.sealString(jsonEncode(answer), key,
          aad: utf8.encode('zt/invite-answer/v1|$inviteId'));
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// Throws when the answer wasn't sealed with this token for [inviteId].
  Future<Map<String, Object?>> openAnswer(
      String inviteId, List<int> sealed) async {
    final key = await Kdf.hkdf(token, 'zt/invite-answer/v1');
    try {
      final clear = await SealedBox.openString(sealed, key,
          aad: utf8.encode('zt/invite-answer/v1|$inviteId'));
      return (jsonDecode(clear) as Map).cast<String, Object?>();
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}

/// The short code two people compare (in person or on a call) when one
/// joins the other's shared space. Both phones compute it from the invite
/// and both identities; if anyone swapped a key on the way, the codes differ.
abstract final class VerificationCode {
  /// Eight digits, shown as "1234 5678".
  static Future<String> compute({
    required String inviteId,
    required List<int> inviterFingerprint,
    required List<int> inviteeFingerprint,
  }) async {
    final digest = (await _sha256.hash([
      ...utf8.encode('zt/verify/v1|$inviteId|'),
      ...inviterFingerprint,
      ...inviteeFingerprint,
    ]))
        .bytes;
    var n = BigInt.zero;
    for (final b in digest.take(8)) {
      n = (n << 8) | BigInt.from(b);
    }
    final digits = (n % BigInt.from(100000000)).toString().padLeft(8, '0');
    return '${digits.substring(0, 4)} ${digits.substring(4)}';
  }
}

final DartX25519 _x25519 = DartX25519();
const DartSha256 _sha256 = DartSha256();

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
