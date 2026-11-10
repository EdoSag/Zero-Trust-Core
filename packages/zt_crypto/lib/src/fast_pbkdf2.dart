import 'dart:convert';
import 'dart:typed_data';

/// PBKDF2-HMAC-SHA256 (RFC 8018), written for speed in pure Dart.
///
/// Gives exactly the bytes `DartPbkdf2(DartHmac(DartSha256()))` gives, about
/// four times faster: HMAC's inner and outer key pads are hashed once instead
/// of on every round, each round is two SHA-256 compressions on preallocated
/// buffers, and nothing is allocated inside the loop. With 600k rounds that
/// is a few seconds instead of ten or more on a mid-range phone
/// (the password unlock after auto-lock).
///
/// Pure Dart on purpose: keys must come out the same in every app and on
/// every device, whatever crypto plugins an app includes.
@pragma('vm:unsafe:no-bounds-checks')
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int length,
}) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
  if (length < 1) throw ArgumentError.value(length, 'length');

  // HMAC key: hashed first if longer than a block, then zero-padded.
  var key = password;
  if (key.length > 64) key = _Sha256.hash(key);
  final ipad = Uint8List(64);
  final opad = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    final b = i < key.length ? key[i] : 0;
    ipad[i] = b ^ 0x36;
    opad[i] = b ^ 0x5c;
  }
  // The states after hashing each pad, reused by every HMAC below.
  final innerState = _Sha256.initialState();
  _Sha256.compressBytes(innerState, ipad);
  final outerState = _Sha256.initialState();
  _Sha256.compressBytes(outerState, opad);

  final out = Uint8List(length);
  final blocks = (length + 31) ~/ 32;
  final state = Uint32List(8);
  final w = Uint32List(64);
  final u = Uint32List(8); // U_j as words
  final t = Uint32List(8); // running XOR
  for (var block = 1; block <= blocks; block++) {
    // U_1 = HMAC(P, S || INT(block)): salt can be any length, so the first
    // round goes through the general path.
    final first = BytesBuilder(copy: false)
      ..add(salt)
      ..add([
        block >> 24 & 0xff,
        block >> 16 & 0xff,
        block >> 8 & 0xff,
        block & 0xff
      ]);
    final inner = _Sha256.finish(innerState, 64, first.takeBytes());
    final u1 = _Sha256.finish(outerState, 64, inner);
    for (var i = 0; i < 8; i++) {
      u[i] = (u1[i * 4] << 24) |
          (u1[i * 4 + 1] << 16) |
          (u1[i * 4 + 2] << 8) |
          u1[i * 4 + 3];
      t[i] = u[i];
    }

    // U_j = HMAC(P, U_{j-1}): a 32-byte message after a 64-byte pad, so the
    // final block is always the same shape (message, 0x80, zeros, length
    // 768 bits). Two compressions per HMAC.
    for (var j = 1; j < iterations; j++) {
      // Inner hash.
      state.setAll(0, innerState);
      for (var i = 0; i < 8; i++) {
        w[i] = u[i];
      }
      w[8] = 0x80000000;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = (64 + 32) * 8;
      _Sha256.compressWords(state, w);
      // Outer hash.
      for (var i = 0; i < 8; i++) {
        w[i] = state[i];
      }
      state.setAll(0, outerState);
      w[8] = 0x80000000;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = (64 + 32) * 8;
      _Sha256.compressWords(state, w);
      for (var i = 0; i < 8; i++) {
        u[i] = state[i];
        t[i] ^= state[i];
      }
    }

    final offset = (block - 1) * 32;
    for (var i = 0; i < 32 && offset + i < length; i++) {
      out[offset + i] = (t[i >> 2] >> (24 - 8 * (i & 3))) & 0xff;
    }
  }
  return out;
}

/// [pbkdf2HmacSha256] with the password as UTF-8, as `DartPbkdf2` takes it.
Uint8List pbkdf2HmacSha256Password({
  required String password,
  required List<int> salt,
  required int iterations,
  required int length,
}) =>
    pbkdf2HmacSha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      length: length,
    );

abstract final class _Sha256 {
  static const List<int> initial = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  static final Uint32List _k = Uint32List.fromList(const [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);

  static Uint32List initialState() => Uint32List.fromList(initial);

  /// SHA-256 of [data].
  static Uint8List hash(List<int> data) => finish(initialState(), 0, data);

  /// Finishes a hash whose state already absorbed [absorbed] bytes, with
  /// [rest] as the remaining message. Leaves [state] untouched.
  static Uint8List finish(Uint32List state, int absorbed, List<int> rest) {
    final s = Uint32List.fromList(state);
    final total = absorbed + rest.length;
    final padded = BytesBuilder(copy: false)
      ..add(rest)
      ..addByte(0x80);
    final zeros = (64 - (rest.length + 1 + 8) % 64) % 64;
    padded.add(Uint8List(zeros));
    final bits = total * 8;
    final len = ByteData(8)
      ..setUint32(0, bits ~/ 0x100000000)
      ..setUint32(4, bits & 0xffffffff);
    padded.add(len.buffer.asUint8List());
    final bytes = padded.takeBytes();
    for (var off = 0; off < bytes.length; off += 64) {
      compressBytes(s, Uint8List.sublistView(bytes, off, off + 64));
    }
    return _digestBytes(s);
  }

  static Uint8List _digestBytes(Uint32List s) {
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = s[i] >> 24;
      out[i * 4 + 1] = s[i] >> 16;
      out[i * 4 + 2] = s[i] >> 8;
      out[i * 4 + 3] = s[i];
    }
    return out;
  }

  static void compressBytes(Uint32List state, List<int> block) {
    final w = Uint32List(64);
    for (var i = 0; i < 16; i++) {
      w[i] = (block[i * 4] << 24) |
          (block[i * 4 + 1] << 16) |
          (block[i * 4 + 2] << 8) |
          block[i * 4 + 3];
    }
    compressWords(state, w);
  }

  /// One SHA-256 compression of the 16 words in [w] (which must have room
  /// for 64; the schedule is expanded in place) into [state].
  @pragma('vm:unsafe:no-bounds-checks')
  static void compressWords(Uint32List state, Uint32List w) {
    final k = _k;
    for (var i = 16; i < 64; i++) {
      final x = w[i - 15];
      final y = w[i - 2];
      final s0 = ((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3);
      final s1 = ((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];
    var f = state[5];
    var g = state[6];
    var h = state[7];
    for (var i = 0; i < 64; i++) {
      final s1 = ((e >> 6) | (e << 26)) ^
          ((e >> 11) | (e << 21)) ^
          ((e >> 25) | (e << 7));
      final ch = (e & f) ^ (~e & g);
      final t1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = ((a >> 2) | (a << 30)) ^
          ((a >> 13) | (a << 19)) ^
          ((a >> 22) | (a << 10));
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }
}
