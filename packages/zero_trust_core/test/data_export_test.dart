import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryItemStore store;
  late InMemoryAttachmentBackend server;
  late ZtAttachments attachments;
  final t = DateTime.utc(2026, 11, 9, 12);

  setUp(() {
    store = InMemoryItemStore();
    server = InMemoryAttachmentBackend();
    attachments = ZtAttachments(
      appId: 'notes',
      userId: 'u1',
      backend: server,
      cache: InMemoryAttachmentCache(),
    );
  });

  Map<String, ArchiveFile> unzip(Uint8List zip) => {
        for (final f in ZipDecoder().decodeBytes(zip).files)
          if (f.isFile) f.name: f,
      };

  Object? jsonOf(ArchiveFile f) => jsonDecode(utf8.decode(f.content));

  test('live items grouped by kind, tombstones left out', () async {
    await store.put(LocalItem(
        itemId: 'n1', updatedAt: t, json: {'title': 'Hello', '_v': 2}));
    await store.put(LocalItem(
        itemId: 'b1',
        updatedAt: t,
        json: {'kind': 'notebook', 'name': 'Work'}));
    await store.put(LocalItem(itemId: 'gone', updatedAt: t, deleted: true));

    final export =
        await ZtDataExporter(appId: 'notes', store: store, now: () => t)
            .build();
    expect(export.fileName, 'zero-trust-notes-2026-11-09.zip');
    expect(export.itemCount, 2);

    final files = unzip(export.zip);
    expect(files.keys, containsAll(['data.json', 'README.txt']));
    final data = jsonOf(files['data.json']!)! as Map;
    expect(data['format'], 'zero-trust-export');
    expect(data['app'], 'notes');
    expect(data['collections'], {
      'items': [
        {
          'id': 'n1',
          'updatedAt': '2026-11-09T12:00:00.000Z',
          'data': {'title': 'Hello', '_v': 2},
        }
      ],
      'notebook': [
        {
          'id': 'b1',
          'updatedAt': '2026-11-09T12:00:00.000Z',
          'data': {'name': 'Work'},
        }
      ],
    });
    expect(
        utf8.decode(files['README.txt']!.content), contains('NOT ENCRYPTED'));
  });

  test('attachments found anywhere in an item are included decrypted',
      () async {
    final photo = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final ref = await attachments.put(photo,
        mimeType: 'image/jpeg', name: '../../etc/beach.jpg');
    final doc = await attachments.put(Uint8List.fromList([1, 2, 3]));
    await store.put(LocalItem(itemId: 'n1', updatedAt: t, json: {
      'images': [ref.toJson()],
      'blocks': [
        {'type': 'file', 'file': doc.toJson()},
        // Not a ref: id isn't 32 hex characters.
        {'id': 'abc', 'key': 'x', 'size': 1},
      ],
    }));

    final export = await ZtDataExporter(
            appId: 'notes', store: store, attachments: attachments)
        .build();
    expect(export.attachmentCount, 2);
    expect(export.missingAttachments, isEmpty);

    final files = unzip(export.zip);
    expect(files['attachments/${ref.id}/beach.jpg']!.content, photo);
    expect(files['attachments/${doc.id}/${doc.id}']!.content, [1, 2, 3]);
    final index = jsonOf(files['attachments/index.json']!)! as List;
    expect(
        index.map((e) => (e as Map)['id']), unorderedEquals([ref.id, doc.id]));
  });

  test('unreadable attachments are listed, not fatal', () async {
    final other = ZtAttachments(
      appId: 'notes',
      userId: 'u1',
      backend: server,
      cache: InMemoryAttachmentCache(),
    );
    server.failWith = Exception('SocketException: offline');
    final ref = await other.put(Uint8List.fromList([9]));
    await store.put(
        LocalItem(itemId: 'n1', updatedAt: t, json: {'image': ref.toJson()}));

    // This device never had the file, and the server is unreachable.
    final export = await ZtDataExporter(
            appId: 'notes', store: store, attachments: attachments)
        .build();
    expect(export.missingAttachments, [ref.id]);
    expect(export.attachmentCount, 0);
    expect(utf8.decode(unzip(export.zip)['README.txt']!.content),
        contains(ref.id));
  });
}
