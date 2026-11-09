import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../attachments/zt_attachments.dart';
import '../sync/local_item_store.dart';

/// The outcome of [ZtDataExporter.build].
class ZtExport {
  const ZtExport({
    required this.zip,
    required this.fileName,
    required this.itemCount,
    required this.attachmentCount,
    required this.missingAttachments,
  });

  /// The ZIP file's bytes. Not encrypted.
  final Uint8List zip;

  /// For example `zero-trust-notes-2026-11-09.zip`.
  final String fileName;
  final int itemCount;
  final int attachmentCount;

  /// Attachment ids that couldn't be read (offline and never downloaded,
  /// or deleted). The README in the ZIP lists them too.
  final List<String> missingAttachments;
}

/// "Export my data" (GDPR portability): every live item of one app,
/// decrypted, as JSON in a ZIP, with its attachments as plain files.
///
/// Layout:
///
/// - `README.txt`: what the files are, and a warning that they aren't
///   encrypted.
/// - `data.json`: `{format, version, app, exportedAt, collections}`, where
///   `collections` maps each item `kind` (`items` for the app's default
///   collection) to a list of `{id, updatedAt, data}`.
/// - `attachments/<id>/<name>`: each attachment found in the items, with
///   `attachments/index.json` mapping ids to file names.
///
/// Attachments are found by shape: any map in an item's JSON that is a
/// [ZtAttachmentRef] (`id` of 32 hex characters, `key`, `size`).
class ZtDataExporter {
  ZtDataExporter({
    required this.appId,
    required this.store,
    this.attachments,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const format = 'zero-trust-export';
  static const formatVersion = 1;

  final String appId;
  final LocalItemStore store;

  /// Null leaves attachments out.
  final ZtAttachments? attachments;
  final DateTime Function() _now;

  static final _hexId = RegExp(r'^[0-9a-f]{32}$');

  Future<ZtExport> build() async {
    final now = _now().toUtc();
    final items = [
      for (final item in await store.all())
        if (!item.deleted && item.json != null) item,
    ]..sort((a, b) => a.itemId.compareTo(b.itemId));

    final collections = <String, List<Map<String, Object?>>>{};
    final refs = <String, ZtAttachmentRef>{};
    for (final item in items) {
      final json = item.json!;
      final kind = json['kind'];
      final data = Map<String, Object?>.of(json)..remove('kind');
      (collections[kind is String ? kind : 'items'] ??= []).add({
        'id': item.itemId,
        'updatedAt': item.updatedAt.toUtc().toIso8601String(),
        'data': data,
      });
      _findRefs(json, refs);
    }

    final archive = Archive();
    void addText(String name, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addText(
        'data.json',
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': formatVersion,
          'app': appId,
          'exportedAt': now.toIso8601String(),
          'collections': collections,
        }));

    final index = <Map<String, Object?>>[];
    final missing = <String>[];
    final source = attachments;
    if (source != null) {
      final usedNames = <String>{};
      for (final ref in refs.values) {
        final Uint8List bytes;
        try {
          bytes = await source.read(ref);
        } on Object {
          missing.add(ref.id);
          continue;
        }
        var path = 'attachments/${ref.id}/${_safeName(ref)}';
        while (!usedNames.add(path)) {
          path = '${path}_';
        }
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
        index.add({
          'id': ref.id,
          'file': path,
          'size': ref.size,
          if (ref.mimeType != null) 'mime': ref.mimeType,
          if (ref.name != null) 'name': ref.name,
        });
      }
      if (index.isNotEmpty) {
        addText('attachments/index.json',
            const JsonEncoder.withIndent('  ').convert(index));
      }
    }

    addText('README.txt', _readme(now, items.length, index.length, missing));

    final zip = ZipEncoder().encodeBytes(archive);
    return ZtExport(
      zip: Uint8List.fromList(zip),
      fileName: 'zero-trust-$appId-${_date(now)}.zip',
      itemCount: items.length,
      attachmentCount: index.length,
      missingAttachments: missing,
    );
  }

  static void _findRefs(Object? value, Map<String, ZtAttachmentRef> into) {
    if (value is Map) {
      final id = value['id'];
      if (id is String &&
          _hexId.hasMatch(id) &&
          value['key'] is String &&
          value['size'] is int) {
        try {
          into[id] = ZtAttachmentRef.fromJson(value.cast<String, Object?>());
          return;
        } on Object {
          // Looks like a ref but isn't one; keep looking inside.
        }
      }
      for (final v in value.values) {
        _findRefs(v, into);
      }
    } else if (value is List) {
      for (final v in value) {
        _findRefs(v, into);
      }
    }
  }

  /// The original name without path parts or characters file systems
  /// reject; the id when there's none.
  static String _safeName(ZtAttachmentRef ref) {
    final name = (ref.name ?? '')
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..') return ref.id;
    return name;
  }

  static String _date(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  String _readme(DateTime now, int items, int files, List<String> missing) =>
      [
        'Zero-Trust $appId export, ${now.toIso8601String()}',
        '',
        'THESE FILES ARE NOT ENCRYPTED. Anyone who gets this file can read',
        'everything in it. Keep it somewhere safe and delete it when done.',
        '',
        'data.json: your $items items as JSON, grouped by kind.',
        if (files > 0)
          'attachments/: $files attached files; index.json says which is which.',
        if (missing.isNotEmpty) ...[
          '',
          '${missing.length} attachments could not be read (not on this',
          'device and no connection, or deleted). Try again online:',
          for (final id in missing) '  $id',
        ],
        '',
      ].join('\n');
}
