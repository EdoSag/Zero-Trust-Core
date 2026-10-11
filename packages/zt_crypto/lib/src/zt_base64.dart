import 'dart:convert';
import 'dart:typed_data';

/// The one base64 dialect every Zero-Trust app writes: URL-safe alphabet,
/// no padding.
///
/// [decode] is deliberately tolerant. Production `profiles.salt` rows were
/// written by four apps in three dialects (unpadded base64url, padded
/// base64url, padded standard base64), and Dart's own decoders reject
/// unpadded input, so an account created in Contacts or Tasks could not be
/// unlocked in Fitness or Notes.
abstract final class ZtBase64 {
  static String encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Accepts standard or URL-safe alphabets, with or without padding, and
  /// ignores surrounding or embedded whitespace.
  static Uint8List decode(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
    if (cleaned.length % 4 == 1) {
      throw FormatException('Invalid base64 length', input);
    }
    final padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
    return Uint8List.fromList(base64Url.decode(padded));
  }
}
