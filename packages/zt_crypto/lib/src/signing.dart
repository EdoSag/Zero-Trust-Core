import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Raw Ed25519 key bytes, so callers can persist them in secure storage
/// without depending on `cryptography`'s key-pair types.
class Ed25519KeyMaterial {
  const Ed25519KeyMaterial({
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });

  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;
}

/// Per-user Ed25519 identity used to sign sync payloads, so Supabase stays an
/// untrusted blob store. Ported from Zero-Trust Notes.
abstract final class Signing {
  static final Ed25519 _ed25519 = Ed25519();

  static Future<Ed25519KeyMaterial> generate() async {
    final keyPair = await _ed25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyMaterial(
      privateKeyBytes: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  static Future<Uint8List> sign(
    List<int> message,
    Ed25519KeyMaterial keys,
  ) async {
    final keyPair = SimpleKeyPairData(
      keys.privateKeyBytes,
      publicKey: SimplePublicKey(keys.publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  static Future<bool> verify(
    List<int> message, {
    required List<int> signature,
    required List<int> publicKey,
  }) =>
      _ed25519.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
}
