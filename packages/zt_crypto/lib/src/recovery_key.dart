import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kdf.dart';

/// The 256-bit key a user writes down at sign-up. It is the only way back
/// into their data after a forgotten password.
///
/// Shown as Crockford base32 in groups of four, with a two-character
/// checksum at the end so a typo is caught before any decryption attempt:
/// `ZT-ABCD-EFGH-…-XY`. Crockford's alphabet has no I, L, O or U, and
/// [parse] maps the look-alikes (I/L→1, O→0) and ignores case, spaces and
/// hyphens.
class RecoveryKey {
  RecoveryKey._(this.bytes);

  static const int length = 32;
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const String _prefix = 'ZT';

  final Uint8List bytes;

  factory RecoveryKey.generate() => RecoveryKey._(Kdf.randomBytes(length));

  factory RecoveryKey.fromBytes(List<int> bytes) {
    if (bytes.length != length) {
      throw ArgumentError('Recovery key must be $length bytes');
    }
    return RecoveryKey._(Uint8List.fromList(bytes));
  }

  /// Formats as `ZT-XXXX-…` for display and printing.
  Future<String> format() async {
    final body = _toBase32(bytes) + await _checksum(bytes);
    final groups = <String>[];
    for (var i = 0; i < body.length; i += 4) {
      groups.add(body.substring(i, i + 4 > body.length ? body.length : i + 4));
    }
    return '$_prefix-${groups.join('-')}';
  }

  /// Throws [FormatException] on a malformed key or a checksum mismatch.
  static Future<RecoveryKey> parse(String input) async {
    var text = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('O', '0');
    if (text.startsWith(_prefix)) text = text.substring(_prefix.length);

    const bodyLength = (length * 8 + 4) ~/ 5; // 52 chars for 32 bytes
    if (text.length != bodyLength + 2) {
      throw FormatException('Recovery key has the wrong length', input);
    }
    final bytes = _fromBase32(text.substring(0, bodyLength));
    if (await _checksum(bytes) != text.substring(bodyLength)) {
      throw FormatException('Recovery key checksum does not match', input);
    }
    return RecoveryKey._(bytes);
  }

  static Future<String> _checksum(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    final v = hash.bytes[0] << 8 | hash.bytes[1];
    return _alphabet[(v >> 5) & 31] + _alphabet[v & 31];
  }

  static String _toBase32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0, bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List _fromBase32(String text) {
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final ch in text.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) throw FormatException('Invalid recovery key character', ch);
      buffer = ((buffer << 5) | v) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    if (out.length != length) {
      throw FormatException('Recovery key decodes to the wrong size', text);
    }
    return Uint8List.fromList(out);
  }
}
