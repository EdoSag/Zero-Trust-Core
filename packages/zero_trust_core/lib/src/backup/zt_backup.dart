import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:zt_crypto/zt_crypto.dart';

import '../attachments/attachment_backend.dart';
import '../attachments/zt_attachments.dart';
import '../config/zt_suite.dart';
import '../export/zt_data_export.dart';
import '../sync/item_sync_engine.dart';
import '../sync/local_item_store.dart';
import '../sync/sync_backend.dart';

/// The file isn't a Zero-Trust backup (or is from a newer app version).
class NotABackup implements Exception {
  const NotABackup([this.newerVersion = false]);

  /// Made by a newer app version: update the app to restore it.
  final bool newerVersion;

  @override
  String toString() => 'NotABackup(newerVersion: $newerVersion)';
}

/// The backup password is wrong.
class WrongBackupPassword implements Exception {
  const WrongBackupPassword();

  @override
  String toString() => 'WrongBackupPassword';
}

/// The file was cut short or changed after it was made.
class BackupDamaged implements Exception {
  const BackupDamaged();

  @override
  String toString() => 'BackupDamaged';
}

/// The account's items of one app, as they were when the backup was made.
class ZtBackupItem {
  const ZtBackupItem(
      {required this.id, required this.updatedAt, required this.json});

  final String id;

  /// Kept on restore, so changes made after the backup win over it.
  final DateTime updatedAt;
  final Map<String, Object?> json;

  Map<String, Object?> toJson() => {
        'id': id,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'json': json,
      };

  static ZtBackupItem fromJson(Map<String, Object?> j) => ZtBackupItem(
        id: j['id']! as String,
        updatedAt: DateTime.parse(j['updatedAt']! as String).toUtc(),
        json: (j['json']! as Map).cast<String, Object?>(),
      );
}

/// What [ZtBackup.open] found in a backup file.
class ZtBackupContents {
  const ZtBackupContents({
    required this.createdAt,
    required this.sourceApp,
    required this.items,
    required this.files,
    required this.missingFiles,
  });

  final DateTime createdAt;

  /// The app the backup was made in.
  final String sourceApp;

  /// Each app's items, by `vault_items` app id.
  final Map<String, List<ZtBackupItem>> items;

  /// Attached files as stored (still sealed with their own keys, which are
  /// in the items), by `<app>/<id>`.
  final Map<String, Uint8List> files;

  /// Files that couldn't be read when the backup was made.
  final int missingFiles;

  int get itemCount => items.values.fold(0, (n, l) => n + l.length);

  /// The apps with at least one item.
  List<String> get apps => [
        for (final e in items.entries)
          if (e.value.isNotEmpty) e.key
      ];
}

/// The outcome of [ZtBackup.create].
class ZtBackupFile {
  const ZtBackupFile({
    required this.bytes,
    required this.fileName,
    required this.contents,
    required this.unreadableItems,
  });

  final Uint8List bytes;

  /// For example `zero-trust-backup-2026-11-23.ztbackup`.
  final String fileName;
  final ZtBackupContents contents;

  /// Rows that failed their signature or didn't decrypt, so were left out.
  final int unreadableItems;
}

/// The outcome of [ZtBackup.restore].
class ZtRestoreResult {
  const ZtRestoreResult(
      {required this.restored, required this.skipped, required this.files});

  /// Items written to the account.
  final int restored;

  /// Items the account already had in the same or a newer version (changed
  /// or deleted after the backup was made). Those changes are kept.
  final int skipped;

  /// Attached files uploaded.
  final int files;
}

/// S-5: one encrypted file with the account's data from every Zero-Trust
/// app, which restores into the same account or a new one, on any phone.
///
/// The data comes from the server, not this device: with the account's
/// data key each app's key is derived ([KeyHierarchy.appKey]) and its rows
/// are checked and opened. Shared spaces are not included (they belong to
/// the space and stay with its members), nor are the suite notes.
///
/// File layout:
///
/// ```
/// "ZTBACKUP" | version (1 byte) | header length (u32 BE) | header JSON
/// then chunks: length (u32 BE) | AES-256-GCM sealed chunk
/// ```
///
/// The header (format, KDF, salt, password check, date) is not secret but
/// is bound into every chunk. The key is PBKDF2 (600k) of the backup
/// password, then HKDF `zt/backup/v1`. Each chunk's AAD is the header, its index and
/// whether it is the last one, so chunks can't be dropped, reordered or
/// cut off unnoticed. The chunks together are a ZIP:
///
/// - `manifest.json`: `{format, version, createdAt, app, apps: {id: n},
///   files: [{app, id}], missingFiles}`
/// - `items/<app>.json`: `[{id, updatedAt, json}]`
/// - `files/<app>/<id>`: each attached file exactly as stored (sealed with
///   its own key, which is in the item that refers to it).
abstract final class ZtBackup {
  static const format = 'zero-trust-backup';
  static const version = 1;
  static const fileExtension = 'ztbackup';
  static final List<int> _magic = ascii.encode('ZTBACKUP');
  static const _chunkSize = 1 << 20;
  static const _keyInfo = 'zt/backup/v1';

  /// The same minimum as account passwords.
  static const minPasswordLength = 12;

  /// Every `vault_items` app a backup covers. Apps not installed simply have
  /// no rows. A new app adds its data app id here (or to [ZtSuite.apps]).
  static const knownApps = [
    'notes', 'tasks', 'fitness', 'contacts', 'calendar', 'phone', //
    'browser', 'time', 'meds', 'quests', 'family', 'home', 'clock',
    'keyboard', 'camera', 'gallery', 'mail', 'messages',
  ];

  static List<String> get apps => {
        ...knownApps,
        for (final app in ZtSuite.apps) app.appId,
      }.toList();

  /// Builds a backup of every app's items and files, sealed with
  /// [password]. [dek] is the account's data key (left as it is).
  ///
  /// Without [files] (or [userId]) attached files are left out and
  /// counted in [ZtBackupContents.missingFiles].
  static Future<ZtBackupFile> create({
    required Uint8List dek,
    required String password,
    required SyncBackend backend,
    required String sourceApp,
    AttachmentBackend? files,
    String? userId,
    Iterable<String>? apps,
    DateTime? now,
    KdfParams params = KdfParams.current,
    void Function(String app)? onApp,
  }) async {
    _checkPassword(password);
    final createdAt = (now ?? DateTime.now()).toUtc();
    final items = <String, List<ZtBackupItem>>{};
    final refs = <String, List<ZtAttachmentRef>>{};
    var unreadable = 0;
    for (final app in apps ?? ZtBackup.apps) {
      onApp?.call(app);
      final codec = await _codec(dek, app);
      try {
        final rows = await backend.pull(app);
        final list = <ZtBackupItem>[];
        for (final row in rows) {
          if (row.deleted) continue;
          final Map<String, Object?>? json;
          try {
            json = await codec.open(row);
          } on Object {
            unreadable++;
            continue;
          }
          if (json == null) continue;
          list.add(ZtBackupItem(
              id: row.itemId, updatedAt: row.updatedAt.toUtc(), json: json));
        }
        list.sort((a, b) => a.id.compareTo(b.id));
        if (list.isEmpty) continue;
        items[app] = list;
        final found = <String, ZtAttachmentRef>{};
        for (final item in list) {
          ZtDataExporter.findAttachmentRefs(item.json, found);
        }
        if (found.isNotEmpty) refs[app] = found.values.toList();
      } finally {
        codec.close();
      }
    }

    final stored = <String, Uint8List>{};
    var missing = 0;
    for (final MapEntry(key: app, value: list) in refs.entries) {
      for (final ref in list) {
        if (files == null || userId == null) {
          missing++;
          continue;
        }
        try {
          final sealed =
              await files.download(ZtBackup._filePath(userId, app, ref.id));
          // Only a file that opens with its own key, at its own size, is
          // backed up; a cut or swapped one counts as missing.
          final plain = await AttachmentCipher.decrypt(sealed,
              key: ref.key, attachmentId: ref.id);
          if (plain.length != ref.size) throw const BackupDamaged();
          plain.fillRange(0, plain.length, 0);
          stored['$app/${ref.id}'] = sealed;
        } on Object {
          missing++;
        }
      }
    }

    final contents = ZtBackupContents(
      createdAt: createdAt,
      sourceApp: sourceApp,
      items: items,
      files: stored,
      missingFiles: missing,
    );
    return ZtBackupFile(
      bytes: await _seal(_zip(contents), password, createdAt, params),
      fileName: 'zero-trust-backup-${_date(createdAt)}.$fileExtension',
      contents: contents,
      unreadableItems: unreadable,
    );
  }

  /// Whether [bytes] start like a backup, without the password. Throws
  /// [NotABackup] otherwise.
  static DateTime checkHeader(Uint8List bytes) =>
      DateTime.parse(_header(bytes).json['createdAt']! as String);

  /// Decrypts and reads a backup made by [create].
  static Future<ZtBackupContents> open(Uint8List bytes, String password) async {
    final header = _header(bytes);
    final json = header.json;
    final kdf = json['kdf'];
    final salt = json['salt'];
    if (kdf is! Map || salt is! String) throw const NotABackup();
    final KdfParams params;
    try {
      params = KdfParams.fromJson(kdf.cast<String, Object?>());
    } on Object {
      throw const NotABackup(true);
    }
    // A file can't make opening it take hours.
    if (params.iterations < 1 || params.iterations > 5000000) {
      throw const NotABackup();
    }
    final (:key, :check) = await _key(password, ZtBase64.decode(salt), params);
    if (check != json['check']) {
      key.fillRange(0, key.length, 0);
      throw const WrongBackupPassword();
    }
    final zip = BytesBuilder(copy: false);
    try {
      var at = header.end;
      var index = 0;
      var last = false;
      while (!last) {
        if (at + 4 > bytes.length) throw const BackupDamaged();
        final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
        at += 4;
        if (length == 0 || at + length > bytes.length) {
          throw const BackupDamaged();
        }
        final sealed = Uint8List.sublistView(bytes, at, at + length);
        at += length;
        last = at == bytes.length;
        try {
          zip.add(await SealedBox.open(sealed, key,
              aad: _chunkAad(header.bytes, index, last)));
        } on Object {
          throw const BackupDamaged();
        }
        index++;
      }
    } finally {
      key.fillRange(0, key.length, 0);
    }
    return _unzip(zip.takeBytes());
  }

  /// Writes [contents] into the signed-in account whose data key is [dek].
  /// Items keep their dates, so whatever the account changed or deleted
  /// after the backup was made stays as it is. Only the files of items
  /// being restored are uploaded, before the items that refer to them.
  static Future<ZtRestoreResult> restore({
    required ZtBackupContents contents,
    required Uint8List dek,
    required SyncBackend backend,
    required String deviceId,
    AttachmentBackend? files,
    String? userId,
    void Function(String app)? onApp,
  }) async {
    var restored = 0;
    var skipped = 0;
    var uploaded = 0;
    for (final MapEntry(key: app, value: list) in contents.items.entries) {
      if (list.isEmpty) continue;
      onApp?.call(app);
      final codec = await _codec(dek, app);
      try {
        for (var i = 0; i < list.length; i += 200) {
          // What the account already has in the same or a newer version
          // is left alone (rewriting it would only make every device
          // download it again).
          final candidates = list.skip(i).take(200).toList();
          final there = {
            for (final row in await backend
                .fetch(app, {for (final item in candidates) item.id}))
              row.itemId: row.updatedAt,
          };
          final batch = [
            for (final item in candidates)
              if (there[item.id] case final at?
                  when !item.updatedAt.isAfter(at))
                null
              else
                item,
          ].nonNulls.toList();
          skipped += candidates.length - batch.length;
          if (batch.isEmpty) continue;
          // Only the files these items refer to, before the items.
          if (files != null && userId != null) {
            final refs = <String, ZtAttachmentRef>{};
            for (final item in batch) {
              ZtDataExporter.findAttachmentRefs(item.json, refs);
            }
            for (final id in refs.keys) {
              final bytes = contents.files['$app/$id'];
              if (bytes == null) continue;
              await files.upload(_filePath(userId, app, id), bytes);
              uploaded++;
            }
          }
          final rows = [
            for (final item in batch)
              await codec.seal(
                  LocalItem(
                      itemId: item.id,
                      updatedAt: item.updatedAt,
                      json: item.json),
                  deviceId),
          ];
          final accepted = await backend.pushAll(app, rows);
          restored += accepted.length;
          skipped += rows.length - accepted.length;
        }
      } finally {
        codec.close();
      }
    }
    return ZtRestoreResult(
        restored: restored, skipped: skipped, files: uploaded);
  }

  static String _filePath(String userId, String app, String id) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const BackupDamaged();
    }
    return '$userId/$app/$id';
  }

  static void _checkPassword(String password) {
    if (password.length < minPasswordLength) {
      throw ArgumentError(
          'Backup password must be at least $minPasswordLength characters.');
    }
  }

  static Future<AppItemCodec> _codec(Uint8List dek, String app) async {
    final appKey = await KeyHierarchy.appKey(dek, app);
    try {
      return AppItemCodec(
        appId: app,
        appKey: appKey,
        signingKeys: await KeyHierarchy.signingKeys(appKey),
      );
    } finally {
      appKey.fillRange(0, appKey.length, 0);
    }
  }

  /// The chunks' key, and a short value that tells a wrong password from a
  /// damaged file (it says no more about the password than the chunks do).
  static Future<({Uint8List key, String check})> _key(
      String password, List<int> salt, KdfParams params) async {
    final master = await Kdf.deriveMasterKey(
        password: password, salt: salt, params: params);
    try {
      return (
        key: await Kdf.hkdf(master, _keyInfo),
        check: ZtBase64.encode(
            await Kdf.hkdf(master, '$_keyInfo/check', length: 16)),
      );
    } finally {
      master.fillRange(0, master.length, 0);
    }
  }

  static List<int> _chunkAad(Uint8List header, int index, bool last) => [
        ...utf8.encode('$_keyInfo|'),
        ...header,
        ...(ByteData(4)..setUint32(0, index)).buffer.asUint8List(),
        if (last) 1 else 0,
      ];

  static Future<Uint8List> _seal(Uint8List plain, String password,
      DateTime createdAt, KdfParams params) async {
    final salt = Kdf.newSalt();
    final (:key, :check) = await _key(password, salt, params);
    final headerJson = utf8.encode(jsonEncode({
      'format': format,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'kdf': params.toJson(),
      'salt': ZtBase64.encode(salt),
      'check': check,
    }));
    final header = BytesBuilder()
      ..add(_magic)
      ..addByte(version)
      ..add((ByteData(4)..setUint32(0, headerJson.length)).buffer.asUint8List())
      ..add(headerJson);
    final headerBytes = header.toBytes();
    final out = BytesBuilder(copy: false)..add(headerBytes);
    try {
      final chunks = (plain.length / _chunkSize).ceil().clamp(1, 1 << 31);
      for (var i = 0; i < chunks; i++) {
        final start = i * _chunkSize;
        final end = (start + _chunkSize).clamp(0, plain.length);
        final sealed = await SealedBox.seal(
            Uint8List.sublistView(plain, start, end), key,
            aad: _chunkAad(headerBytes, i, i == chunks - 1));
        out
          ..add((ByteData(4)..setUint32(0, sealed.length)).buffer.asUint8List())
          ..add(sealed);
      }
    } finally {
      key.fillRange(0, key.length, 0);
    }
    return out.takeBytes();
  }

  static ({Map<String, Object?> json, Uint8List bytes, int end}) _header(
      Uint8List bytes) {
    final fixed = _magic.length + 1 + 4;
    if (bytes.length < fixed) throw const NotABackup();
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) throw const NotABackup();
    }
    if (bytes[_magic.length] != version) throw const NotABackup(true);
    final length =
        ByteData.sublistView(bytes, _magic.length + 1, fixed).getUint32(0);
    if (length > 64 * 1024 || fixed + length > bytes.length) {
      throw const NotABackup();
    }
    final Object? json;
    try {
      json = jsonDecode(
          utf8.decode(Uint8List.sublistView(bytes, fixed, fixed + length)));
    } on FormatException {
      throw const NotABackup();
    }
    if (json is! Map || json['format'] != format) throw const NotABackup();
    if (json['version'] != version) throw const NotABackup(true);
    if (json['createdAt'] is! String ||
        DateTime.tryParse(json['createdAt'] as String) == null) {
      throw const NotABackup();
    }
    return (
      json: json.cast<String, Object?>(),
      bytes: Uint8List.sublistView(bytes, 0, fixed + length),
      end: fixed + length,
    );
  }

  static Uint8List _zip(ZtBackupContents c) {
    final archive = Archive();
    void addJson(String name, Object json) =>
        archive.addFile(ArchiveFile.string(name, jsonEncode(json)));
    addJson('manifest.json', {
      'format': format,
      'version': version,
      'createdAt': c.createdAt.toIso8601String(),
      'app': c.sourceApp,
      'apps': {for (final e in c.items.entries) e.key: e.value.length},
      'files': [
        for (final path in c.files.keys)
          {
            'app': path.substring(0, path.indexOf('/')),
            'id': path.substring(path.indexOf('/') + 1),
          }
      ],
      'missingFiles': c.missingFiles,
    });
    for (final MapEntry(key: app, value: list) in c.items.entries) {
      addJson('items/$app.json', [for (final item in list) item.toJson()]);
    }
    for (final MapEntry(key: path, value: bytes) in c.files.entries) {
      // Already sealed: compressing would only cost time.
      archive.addFile(ArchiveFile.bytes('files/$path', bytes)
        ..compression = CompressionType.none);
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  static final _appPattern = RegExp(r'^[a-z_]+$');

  static ZtBackupContents _unzip(Uint8List zip) {
    try {
      final archive = ZipDecoder().decodeBytes(zip);
      Object? readJson(String name) {
        final file = archive.findFile(name);
        if (file == null) throw const BackupDamaged();
        return jsonDecode(utf8.decode(file.content));
      }

      final manifest =
          (readJson('manifest.json')! as Map).cast<String, Object?>();
      if (manifest['format'] != format) throw const BackupDamaged();
      final items = <String, List<ZtBackupItem>>{};
      for (final app in (manifest['apps']! as Map).keys.cast<String>()) {
        if (!_appPattern.hasMatch(app)) throw const BackupDamaged();
        items[app] = [
          for (final j in readJson('items/$app.json')! as List)
            ZtBackupItem.fromJson((j as Map).cast<String, Object?>()),
        ];
      }
      final files = <String, Uint8List>{};
      for (final f in manifest['files']! as List) {
        final app = (f as Map)['app'] as String;
        final id = f['id'] as String;
        if (!_appPattern.hasMatch(app)) throw const BackupDamaged();
        final file = archive.findFile('files/$app/$id');
        if (file == null) throw const BackupDamaged();
        files['$app/$id'] = Uint8List.fromList(file.content);
      }
      return ZtBackupContents(
        createdAt: DateTime.parse(manifest['createdAt']! as String).toUtc(),
        sourceApp: manifest['app'] as String? ?? '',
        items: items,
        files: files,
        missingFiles: (manifest['missingFiles'] as int?) ?? 0,
      );
    } on BackupDamaged {
      rethrow;
    } on Object {
      throw const BackupDamaged();
    }
  }

  static String _date(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
