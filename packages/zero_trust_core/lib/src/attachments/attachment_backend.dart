import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Where encrypted attachment files live on the server. Paths are
/// `{user_id}/{app}/{attachment_id}`; the server only ever sees ciphertext.
abstract interface class AttachmentBackend {
  /// Uploads [bytes] to [path], replacing any earlier upload there (a retry
  /// after a lost response must not fail).
  Future<void> upload(String path, Uint8List bytes);

  /// Throws [AttachmentNotFound] when nothing is stored at [path].
  Future<Uint8List> download(String path);

  /// Removes [paths]. Missing paths are not an error.
  Future<void> remove(List<String> paths);
}

class AttachmentNotFound implements Exception {
  const AttachmentNotFound(this.path);
  final String path;
  @override
  String toString() => 'AttachmentNotFound($path)';
}

class InMemoryAttachmentBackend implements AttachmentBackend {
  final Map<String, Uint8List> files = {};

  /// Set to make every call fail, as when offline.
  Object? failWith;

  void _check() {
    final e = failWith;
    if (e != null) throw e;
  }

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    _check();
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> download(String path) async {
    _check();
    return files[path] ?? (throw AttachmentNotFound(path));
  }

  @override
  Future<void> remove(List<String> paths) async {
    _check();
    paths.forEach(files.remove);
  }
}

/// [AttachmentBackend] over the private `zt-attachments` Storage bucket
/// (policies: a user reads and writes only under their own id).
class SupabaseAttachmentBackend implements AttachmentBackend {
  SupabaseAttachmentBackend([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const bucket = 'zt-attachments';

  StorageFileApi get _files => _client.storage.from(bucket);

  @override
  Future<void> upload(String path, Uint8List bytes) => _files.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'application/octet-stream',
        ),
      );

  @override
  Future<Uint8List> download(String path) async {
    try {
      return await _files.download(path);
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.statusCode == '400') {
        throw AttachmentNotFound(path);
      }
      rethrow;
    }
  }

  @override
  Future<void> remove(List<String> paths) async {
    if (paths.isEmpty) return;
    await _files.remove(paths);
  }
}
