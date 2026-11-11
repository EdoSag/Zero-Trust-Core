import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

/// An invite to a shared space, as a link (to send in a message) or a QR
/// code (to scan in person); both carry the same text.
///
/// Everything after `#` stays on the phones: browsers never send a link's
/// fragment to a server, so the token and fingerprint don't reach
/// zerotrust.bz either.
///
/// `https://zerotrust.bz/join#zt1.<app>.<invite>.<token>.<inviter>.<fp>`
class SpaceInviteLink {
  SpaceInviteLink({
    required this.app,
    required this.inviteId,
    required this.secret,
    required this.inviterUserId,
    required List<int> inviterFingerprint,
  }) : inviterFingerprint = Uint8List.fromList(inviterFingerprint);

  static const String base = 'https://zerotrust.bz/join';
  static const String _version = 'zt1';

  final String app;
  final String inviteId;
  final InviteSecret secret;
  final String inviterUserId;

  /// The inviter's identity fingerprint: the joiner trusts the space's
  /// member list only as far as it starts from this key.
  final Uint8List inviterFingerprint;

  @override
  String toString() => '$base#$_version.$app.$inviteId.'
      '${ZtBase64.encode(secret.token)}.$inviterUserId.'
      '${ZtBase64.encode(inviterFingerprint)}';

  /// The QR code's content: the link itself, so a phone without the app
  /// still lands on the download page.
  String get qrData => toString();

  /// Reads a pasted or scanned link. Accepts the bare fragment too. Throws
  /// [FormatException] for anything else.
  static SpaceInviteLink parse(String input) {
    final text = input.trim();
    final hash = text.indexOf('#');
    final fragment = hash >= 0 ? text.substring(hash + 1) : text;
    final parts = fragment.split('.');
    if (parts.length != 6 || parts[0] != _version) {
      throw const FormatException('Not a Zero-Trust invite link');
    }
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
        r'[0-9a-f]{4}-[0-9a-f]{12}$');
    if (!RegExp(r'^[a-z_]+$').hasMatch(parts[1]) ||
        !uuid.hasMatch(parts[2]) ||
        !uuid.hasMatch(parts[4])) {
      throw const FormatException('Not a Zero-Trust invite link');
    }
    try {
      final token = ZtBase64.decode(parts[3]);
      final fp = ZtBase64.decode(parts[5]);
      if (token.length != 32 || fp.length != 32) throw const FormatException();
      return SpaceInviteLink(
        app: parts[1],
        inviteId: parts[2],
        secret: InviteSecret(token),
        inviterUserId: parts[4],
        inviterFingerprint: fp,
      );
    } on Object {
      throw const FormatException('Not a Zero-Trust invite link');
    }
  }
}

/// A random (version 4) UUID, for space and invite ids made on the device.
String newUuid() {
  final b = Kdf.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
