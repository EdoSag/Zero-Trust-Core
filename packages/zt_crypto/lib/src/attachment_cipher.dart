import 'dart:convert';
import 'dart:typed_data';

import 'sealed_box.dart';

/// Thrown when an encrypted attachment is truncated, reordered, tampered
/// with, or opened with the wrong key or id.
class AttachmentCorrupt implements Exception {
  const AttachmentCorrupt(this.reason);
  final String reason;
  @override
  String toString() => 'AttachmentCorrupt($reason)';
}

/// File encryption for attachments (images, photos, recordings).
///
/// Each attachment has its own random 256-bit content key, kept inside the
/// owning item's (already encrypted) JSON, never next to the file. The file
/// is cut into chunks, each an AES-256-GCM [SealedBox] whose AAD binds it to
/// the attachment id, its position and whether it is the last chunk. So a
/// server can't swap files between attachments, reorder, drop or append
/// chunks, or cut the file short without decryption failing.
///
/// Layout: `"ZTA1"` · chunk size (u32 BE) · chunk count (u32 BE) · chunks,
/// each `nonce(12) || ciphertext || mac(16)`. Every chunk but the last holds
/// exactly the chunk size; the format allows decrypting chunk by chunk
/// (streaming) later without changing what's stored.
abstract final class AttachmentCipher {
  static const _magic = [0x5A, 0x54, 0x41, 0x31]; // ZTA1
  static const _headerLength = 12;
  static const _overhead = 12 + 16;

  /// 256 KiB: small enough to stream, large enough that the per-chunk
  /// overhead (28 bytes) is negligible.
  static const defaultChunkSize = 256 * 1024;

  static Future<Uint8List> encrypt(
    List<int> plaintext, {
    required List<int> key,
    required String attachmentId,
    int chunkSize = defaultChunkSize,
  }) async {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    final count =
        plaintext.isEmpty ? 1 : (plaintext.length + chunkSize - 1) ~/ chunkSize;
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(_u32(chunkSize))
      ..add(_u32(count));
    for (var i = 0; i < count; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize).clamp(0, plaintext.length);
      out.add(await SealedBox.seal(
        plaintext.sublist(start, end),
        key,
        aad: _aad(attachmentId, i, last: i == count - 1),
      ));
    }
    return out.takeBytes();
  }

  static Future<Uint8List> decrypt(
    List<int> sealed, {
    required List<int> key,
    required String attachmentId,
  }) async {
    if (sealed.length < _headerLength) {
      throw const AttachmentCorrupt('too short');
    }
    for (var i = 0; i < 4; i++) {
      if (sealed[i] != _magic[i]) throw const AttachmentCorrupt('not ZTA1');
    }
    final chunkSize = _readU32(sealed, 4);
    final count = _readU32(sealed, 8);
    if (chunkSize == 0 || count == 0) {
      throw const AttachmentCorrupt('bad header');
    }
    final out = BytesBuilder(copy: false);
    var offset = _headerLength;
    for (var i = 0; i < count; i++) {
      final last = i == count - 1;
      final end = last ? sealed.length : offset + chunkSize + _overhead;
      if (end > sealed.length || end - offset < _overhead) {
        throw const AttachmentCorrupt('truncated');
      }
      try {
        out.add(await SealedBox.open(
          sealed.sublist(offset, end),
          key,
          aad: _aad(attachmentId, i, last: last),
        ));
      } on Object {
        throw AttachmentCorrupt('chunk $i failed authentication');
      }
      offset = end;
    }
    return out.takeBytes();
  }

  /// The encrypted size for [plaintextLength] bytes.
  static int encryptedLength(int plaintextLength,
      {int chunkSize = defaultChunkSize}) {
    final count = plaintextLength == 0
        ? 1
        : (plaintextLength + chunkSize - 1) ~/ chunkSize;
    return _headerLength + plaintextLength + count * _overhead;
  }

  static List<int> _aad(String id, int index, {required bool last}) => [
        ...utf8.encode('zt/attachment/v1/$id'),
        ..._u32(index),
        last ? 1 : 0,
      ];

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static int _readU32(List<int> b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
}
