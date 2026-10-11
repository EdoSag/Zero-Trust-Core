import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Password KDF parameters, stored next to the salt in `profiles.kdf_params`
/// so iterations (or the algorithm) can be raised later without breaking
/// existing accounts.
class KdfParams {
  const KdfParams({this.algorithm = pbkdf2Sha256, this.iterations = 600000});

  static const String pbkdf2Sha256 = 'pbkdf2-sha256';

  /// What every app uses today; also the v2 default.
  static const KdfParams current = KdfParams();

  final String algorithm;
  final int iterations;

  Map<String, Object> toJson() => {'alg': algorithm, 'iter': iterations};

  factory KdfParams.fromJson(Map<String, Object?> json) {
    final alg = json['alg'] as String? ?? pbkdf2Sha256;
    if (alg != pbkdf2Sha256) {
      throw UnsupportedError('Unsupported KDF: $alg');
    }
    return KdfParams(algorithm: alg, iterations: json['iter'] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.algorithm == algorithm &&
      other.iterations == iterations;

  @override
  int get hashCode => Object.hash(algorithm, iterations);
}

abstract final class Kdf {
  static const int keyLength = 32;
  static const int saltLength = 16;

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List newSalt() => randomBytes(saltLength);

  /// The v2 KDF salt, derived from the account email so a device can compute
  /// the Supabase auth secret before it is signed in (profiles are behind
  /// RLS). Same approach as Bitwarden. The domain prefix keeps it from
  /// matching any other service's salt for the same email.
  static Future<Uint8List> saltForEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final hash = await Sha256().hash(utf8.encode('zerotrust/kdf-salt/v2/$normalized'));
    return Uint8List.fromList(hash.bytes.sublist(0, saltLength));
  }

  /// Stretches the password into the 32-byte master key. The result never
  /// leaves the device and is never stored.
  static Future<Uint8List> deriveMasterKey({
    required String password,
    required List<int> salt,
    KdfParams params = KdfParams.current,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: keyLength * 8,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// HKDF-SHA256 expansion of [key] into an independent subkey for [info].
  /// Distinct `info` strings give keys that reveal nothing about each other.
  static Future<Uint8List> hkdf(
    List<int> key,
    String info, {
    List<int> salt = const [],
    int length = keyLength,
  }) async {
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: length)
        .deriveKey(
      secretKey: SecretKey(key),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }
}
