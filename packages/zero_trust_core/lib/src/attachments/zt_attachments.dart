import 'dart:async';
import 'dart:typed_data';

import 'package:zt_crypto/zt_crypto.dart';

import 'attachment_backend.dart';
import 'attachment_cache.dart';

/// A file attached to an item. Store [toJson] inside the item's JSON (which
/// is itself encrypted), for example `note.images`: the content [key] lives
/// only there, never next to the file.
class ZtAttachmentRef {
  const ZtAttachmentRef({
    required this.id,
    required this.key,
    required this.size,
    this.mimeType,
    this.name,
  });

  factory ZtAttachmentRef.fromJson(Map<String, Object?> json) =>
      ZtAttachmentRef(
        id: json['id'] as String,
        key: ZtBase64.decode(json['key'] as String),
        size: json['size'] as int,
        mimeType: json['mime'] as String?,
        name: json['name'] as String?,
      );

  /// 32 lowercase hex characters.
  final String id;

  /// The attachment's own random AES-256 key.
  final Uint8List key;

  /// Plaintext size in bytes.
  final int size;
  final String? mimeType;

  /// Original file name, if the app wants to show one.
  final String? name;

  Map<String, Object?> toJson() => {
        'id': id,
        'key': ZtBase64.encode(key),
        'size': size,
        if (mimeType != null) 'mime': mimeType,
        if (name != null) 'name': name,
      };

  @override
  bool operator ==(Object other) => other is ZtAttachmentRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class AttachmentTooLarge implements Exception {
  const AttachmentTooLarge(this.size, this.limit);
  final int size;
  final int limit;
  @override
  String toString() => 'AttachmentTooLarge($size > $limit)';
}

/// Encrypted attachments for one app and account.
///
/// - [put] encrypts on the device and keeps the encrypted file locally, so
///   it shows at once and offline. The upload happens right away when
///   online, otherwise on a later [flush] (the core calls it after every
///   successful sync).
/// - [read] uses the local copy, or downloads and keeps one.
/// - [delete] removes both copies; an offline delete is retried by [flush].
///
/// Deleting an item doesn't delete its attachments by itself: call [delete]
/// for each ref the item held (or [deleteAll]) when the app deletes it.
class ZtAttachments {
  ZtAttachments({
    required this.appId,
    required this.userId,
    required AttachmentBackend backend,
    required AttachmentCache cache,
    this.maxBytes = defaultMaxBytes,
  })  : _backend = backend,
        _cache = cache;

  /// 20 MB, matching the bucket's limit after encryption overhead.
  static const defaultMaxBytes = 20 * 1000 * 1000;

  final String appId;
  final String userId;
  final int maxBytes;
  final AttachmentBackend _backend;
  final AttachmentCache _cache;
  Future<void>? _flushing;

  String pathOf(String id) => '$userId/$appId/$id';

  /// Encrypts and stores [bytes]; returns the ref to keep in the item.
  /// Never fails for lack of network.
  Future<ZtAttachmentRef> put(
    Uint8List bytes, {
    String? mimeType,
    String? name,
  }) async {
    if (bytes.length > maxBytes) {
      throw AttachmentTooLarge(bytes.length, maxBytes);
    }
    final id = Kdf.randomBytes(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final key = Kdf.randomBytes(32);
    final sealed =
        await AttachmentCipher.encrypt(bytes, key: key, attachmentId: id);
    await _cache.write(id, sealed);
    await _cache.setPendingUploads({...await _cache.pendingUploads(), id});
    final ref = ZtAttachmentRef(
        id: id, key: key, size: bytes.length, mimeType: mimeType, name: name);
    unawaited(flush().catchError((Object _) {}));
    return ref;
  }

  /// The decrypted file. Throws [AttachmentNotFound] if it was never
  /// uploaded from the device that added it, or was deleted, and
  /// [AttachmentCorrupt] if the stored file was tampered with.
  Future<Uint8List> read(ZtAttachmentRef ref) async {
    var sealed = await _cache.read(ref.id);
    final cached = sealed != null;
    sealed ??= await _backend.download(pathOf(ref.id));
    final plain = await AttachmentCipher.decrypt(sealed,
        key: ref.key, attachmentId: ref.id);
    if (plain.length != ref.size) {
      throw const AttachmentCorrupt('size does not match');
    }
    if (!cached) await _cache.write(ref.id, sealed);
    return plain;
  }

  /// Whether [ref]'s file is on this device (readable offline).
  Future<bool> isOnDevice(ZtAttachmentRef ref) async =>
      await _cache.read(ref.id) != null;

  Future<void> delete(ZtAttachmentRef ref) => deleteAll([ref]);

  Future<void> deleteAll(Iterable<ZtAttachmentRef> refs) async {
    final ids = {for (final r in refs) r.id};
    if (ids.isEmpty) return;
    for (final id in ids) {
      await _cache.remove(id);
    }
    await _cache
        .setPendingUploads((await _cache.pendingUploads()).difference(ids));
    await _cache.setPendingDeletes({...await _cache.pendingDeletes(), ...ids});
    unawaited(flush().catchError((Object _) {}));
  }

  /// Retries waiting uploads and deletes. Throws the first network error,
  /// leaving the rest for the next call. Runs one at a time.
  Future<void> flush() {
    final previous = _flushing ?? Future<void>.value();
    late final Future<void> next;
    next = previous.catchError((Object _) {}).then((_) => _flush())
      ..whenComplete(() {
        if (identical(_flushing, next)) _flushing = null;
      }).ignore();
    _flushing = next;
    return next;
  }

  Future<void> _flush() async {
    final deletes = await _cache.pendingDeletes();
    if (deletes.isNotEmpty) {
      await _backend.remove([for (final id in deletes) pathOf(id)]);
      await _cache.setPendingDeletes(
          (await _cache.pendingDeletes()).difference(deletes));
    }
    for (final id in await _cache.pendingUploads()) {
      final sealed = await _cache.read(id);
      if (sealed != null) await _backend.upload(pathOf(id), sealed);
      await _cache
          .setPendingUploads((await _cache.pendingUploads())..remove(id));
    }
  }

  /// How many uploads are still waiting for the network.
  Future<int> pendingUploadCount() async =>
      (await _cache.pendingUploads()).length;
}
