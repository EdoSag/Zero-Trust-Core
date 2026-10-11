import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM sealed box: `nonce(12) || ciphertext || mac(16)`.
///
/// Same wire format Notes already writes, so existing Notes ciphertext reads
/// unchanged. [aad] binds a ciphertext to its context (for example the item
/// id), so a server cannot swap one valid blob in for another.
abstract final class SealedBox {
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<Uint8List> seal(
    List<int> plaintext,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws [SecretBoxAuthenticationError] on a wrong key, wrong [aad] or
  /// any tampering.
  static Future<Uint8List> open(
    List<int> sealed,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return Uint8List.fromList(
      await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad),
    );
  }

  static Future<Uint8List> sealString(
    String plaintext,
    List<int> key, {
    List<int> aad = const [],
  }) =>
      seal(utf8.encode(plaintext), key, aad: aad);

  static Future<String> openString(
    List<int> sealed,
    List<int> key, {
    List<int> aad = const [],
  }) async =>
      utf8.decode(await open(sealed, key, aad: aad));
}
