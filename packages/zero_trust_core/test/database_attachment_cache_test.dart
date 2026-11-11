import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('zt_att'));
  tearDown(() => dir.delete(recursive: true));

  test('keeps sealed files and waiting work across reopening', () async {
    final path = '${dir.path}/zt_attachments_notes_u.db';
    var cache = await DatabaseAttachmentCache.open(path);
    await cache.write('a' * 32, Uint8List.fromList([1, 2, 3]));
    await cache.setPendingUploads({'a' * 32});
    await cache.setPendingDeletes({'b' * 32, 'c' * 32});
    await cache.close();

    cache = await DatabaseAttachmentCache.open(path);
    addTearDown(cache.close);
    expect(await cache.read('a' * 32), [1, 2, 3]);
    expect(await cache.pendingUploads(), {'a' * 32});
    expect(await cache.pendingDeletes(), {'b' * 32, 'c' * 32});

    await cache.setPendingDeletes({});
    await cache.remove('a' * 32);
    expect(await cache.read('a' * 32), isNull);
    expect(await cache.pendingDeletes(), isEmpty);
    expect(await cache.pendingUploads(), {'a' * 32});
  });
}
