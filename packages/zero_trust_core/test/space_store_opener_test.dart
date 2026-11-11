import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  late Directory dir;
  late Uint8List appKey;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zt_space_store');
    appKey = await KeyHierarchy.appKey(
        Uint8List.fromList(List.generate(32, (i) => i)), 'notes');
  });
  tearDown(() => dir.delete(recursive: true));

  String path(String spaceId) => '${dir.path}/space_$spaceId.db';

  ZtSpaceStoreOpener opener({Future<void>? wait}) => ZtSpaceStoreOpener(
      appKey: appKey,
      appId: 'notes',
      userId: 'u1',
      pathFor: (id) async {
        await wait;
        return path(id);
      });

  Iterable<FileSystemEntity> movedAside() =>
      dir.listSync().where((f) => f.path.contains('.unreadable-'));

  test('opens each space once and closes them all', () async {
    final o = opener();
    final both = await Future.wait([o.open('s1'), o.open('s1')]);
    expect(both[0], same(both[1]));
    expect(await o.open('s1'), same(both[0]));
    await both[0].put(LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026)));
    await o.closeAll();
    expect(() => o.open('s1'), throwsA(isA<VaultIsLocked>()));

    // The same key reads it back.
    final again = opener();
    expect((await (await again.open('s1')).all()).single.itemId, 'a');
    await again.closeAll();
  });

  test('a lock while a space is opening keeps its file and leaves nothing open',
      () async {
    final first = opener();
    await (await first.open('s1')).put(
        LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026), dirty: true));
    await first.closeAll();

    final gate = Completer<void>();
    final o = opener(wait: gate.future);
    final opening = o.open('s1');
    final failed = expectLater(opening, throwsA(isA<VaultIsLocked>()));
    // The vault locks (the key is zeroed) before the path is known.
    final closing = o.closeAll();
    gate.complete();
    await failed;
    await closing;
    expect(movedAside(), isEmpty);

    // The unsynced edit is still there after the next unlock.
    final next = opener();
    final item = (await (await next.open('s1')).all()).single;
    expect(item.itemId, 'a');
    expect(item.dirty, isTrue);
    await next.closeAll();
  });

  test('a space that is stuck opening does not hold up closing the others',
      () async {
    final stuck = Completer<void>();
    final o = ZtSpaceStoreOpener(
        appKey: appKey,
        appId: 'notes',
        userId: 'u1',
        pathFor: (id) async {
          if (id == 's2') await stuck.future;
          return path(id);
        });
    final open = await o.open('s1');
    await open.put(LocalItem(itemId: 'a', updatedAt: DateTime.utc(2026)));
    final opening = o.open('s2');
    final failed = expectLater(opening, throwsA(isA<VaultIsLocked>()));

    // Returns with s2 still stuck, and s1 is closed.
    await o.closeAll().timeout(const Duration(seconds: 5));
    await expectLater(open.all(), throwsA(anything));

    stuck.complete();
    await failed;
    expect(File(path('s2')).existsSync(), isFalse);
  });

  test('delete removes the files of an open space', () async {
    final o = opener();
    await o.open('s1');
    await o.delete('s1');
    expect(File(path('s1')).existsSync(), isFalse);
    expect(await (await o.open('s1')).all(), isEmpty);
    await o.closeAll();
  });
}
