import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The device's copy of encrypted attachment files, plus the uploads and
/// deletes still waiting for the network. Holds ciphertext only, so it
/// needs no protection of its own.
abstract interface class AttachmentCache {
  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List sealed);
  Future<void> remove(String id);

  Future<Set<String>> pendingUploads();
  Future<Set<String>> pendingDeletes();
  Future<void> setPendingUploads(Set<String> ids);
  Future<void> setPendingDeletes(Set<String> ids);
}

class InMemoryAttachmentCache implements AttachmentCache {
  final Map<String, Uint8List> files = {};
  Set<String> uploads = {};
  Set<String> deletes = {};

  @override
  Future<Uint8List?> read(String id) async => files[id];
  @override
  Future<void> write(String id, Uint8List sealed) async => files[id] = sealed;
  @override
  Future<void> remove(String id) async => files.remove(id);
  @override
  Future<Set<String>> pendingUploads() async => {...uploads};
  @override
  Future<Set<String>> pendingDeletes() async => {...deletes};
  @override
  Future<void> setPendingUploads(Set<String> ids) async => uploads = {...ids};
  @override
  Future<void> setPendingDeletes(Set<String> ids) async => deletes = {...ids};
}

/// [AttachmentCache] in a folder per app and account under the app's
/// support directory.
class FileAttachmentCache implements AttachmentCache {
  FileAttachmentCache(this.dir);

  final Directory dir;

  static Future<FileAttachmentCache> forAccount({
    required String appId,
    required String userId,
  }) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/zt_attachments_${appId}_$userId');
    await dir.create(recursive: true);
    return FileAttachmentCache(dir);
  }

  /// Deletes the cache folder, for example after account deletion.
  static Future<void> deleteFor({
    required String appId,
    required String userId,
  }) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/zt_attachments_${appId}_$userId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static int _tmpCount = 0;
  static String _tmpSuffix() =>
      'tmp${DateTime.now().microsecondsSinceEpoch}-${_tmpCount++}';

  static final _safeId = RegExp(r'^[0-9a-f]{32}$');

  File _file(String id) {
    if (!_safeId.hasMatch(id)) throw ArgumentError.value(id, 'id');
    return File('${dir.path}/$id.zta');
  }

  File get _pending => File('${dir.path}/pending.json');

  @override
  Future<Uint8List?> read(String id) async {
    final f = _file(id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String id, Uint8List sealed) async {
    // Write then rename, so a crash never leaves half a file behind.
    final tmp = File('${_file(id).path}.${_tmpSuffix()}');
    await tmp.writeAsBytes(sealed, flush: true);
    await tmp.rename(_file(id).path);
  }

  @override
  Future<void> remove(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }

  Future<Map<String, Set<String>>> _readPending() async {
    if (!await _pending.exists()) return {'uploads': {}, 'deletes': {}};
    try {
      final json = jsonDecode(await _pending.readAsString()) as Map;
      return {
        for (final k in ['uploads', 'deletes'])
          k: {...((json[k] as List?) ?? const []).whereType<String>()},
      };
    } on FormatException {
      return {'uploads': {}, 'deletes': {}};
    }
  }

  Future<void> _writePending(Map<String, Set<String>> p) async {
    final tmp = File('${_pending.path}.${_tmpSuffix()}');
    await tmp.writeAsString(jsonEncode({
      for (final e in p.entries) e.key: e.value.toList(),
    }));
    await tmp.rename(_pending.path);
  }

  @override
  Future<Set<String>> pendingUploads() async =>
      (await _readPending())['uploads']!;

  @override
  Future<Set<String>> pendingDeletes() async =>
      (await _readPending())['deletes']!;

  @override
  Future<void> setPendingUploads(Set<String> ids) async =>
      _writePending({...await _readPending(), 'uploads': ids});

  @override
  Future<void> setPendingDeletes(Set<String> ids) async =>
      _writePending({...await _readPending(), 'deletes': ids});
}
