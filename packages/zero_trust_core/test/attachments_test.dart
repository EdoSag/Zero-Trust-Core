import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryAttachmentBackend server;
  late InMemoryAttachmentCache cache;
  late ZtAttachments attachments;

  ZtAttachments onDevice(InMemoryAttachmentCache cache) => ZtAttachments(
        appId: 'notes',
        userId: 'u1',
        backend: server,
        cache: cache,
        maxBytes: 1000000,
      );

  setUp(() {
    server = InMemoryAttachmentBackend();
    cache = InMemoryAttachmentCache();
    attachments = onDevice(cache);
  });

  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (i) => i % 251));

  test('put encrypts, uploads, and another device reads it back', () async {
    final photo = bytes(600000); // several chunks
    final ref = await attachments.put(photo, mimeType: 'image/jpeg');
    await attachments.flush();

    final stored = server.files['u1/notes/${ref.id}']!;
    expect(stored.length, AttachmentCipher.encryptedLength(photo.length));
    // Ciphertext only: the plaintext's first bytes don't appear.
    expect(stored.sublist(12, 40), isNot(photo.sublist(0, 28)));

    // The ref travels inside the item's JSON.
    final copied = ZtAttachmentRef.fromJson(ref.toJson());
    final other = onDevice(InMemoryAttachmentCache());
    expect(await other.isOnDevice(copied), isFalse);
    expect(await other.read(copied), photo);
    expect(await other.isOnDevice(copied), isTrue);
  });

  test('offline: put works, read works locally, upload waits for flush',
      () async {
    server.failWith = Exception('SocketException: offline');
    final ref = await attachments.put(bytes(10));
    await pumpEventQueue();
    expect(await attachments.read(ref), bytes(10));
    expect(await attachments.pendingUploadCount(), 1);
    await expectLater(attachments.flush(), throwsA(anything));

    server.failWith = null;
    await attachments.flush();
    expect(await attachments.pendingUploadCount(), 0);
    expect(server.files, hasLength(1));
  });

  test('delete removes both copies, retried after an offline delete', () async {
    final ref = await attachments.put(bytes(10));
    await attachments.flush();
    server.failWith = Exception('offline');
    await attachments.delete(ref);
    await pumpEventQueue();
    expect(await attachments.isOnDevice(ref), isFalse);
    expect(server.files, hasLength(1));

    server.failWith = null;
    await attachments.flush();
    expect(server.files, isEmpty);
  });

  test('deleted before it was ever uploaded: never uploaded', () async {
    server.failWith = Exception('offline');
    final ref = await attachments.put(bytes(10));
    await attachments.delete(ref);
    server.failWith = null;
    await attachments.flush();
    expect(server.files, isEmpty);
  });

  test('a swapped, truncated or tampered file is refused', () async {
    final a = await attachments.put(bytes(300000));
    final b = await attachments.put(bytes(20));
    await attachments.flush();
    final fresh = onDevice(InMemoryAttachmentCache());

    // The server swaps b's file in for a.
    server.files['u1/notes/${a.id}'] = server.files['u1/notes/${b.id}']!;
    await expectLater(fresh.read(a), throwsA(isA<AttachmentCorrupt>()));

    final good = await AttachmentCipher.encrypt(bytes(300000),
        key: a.key, attachmentId: a.id);
    // Cut after the first chunk.
    server.files['u1/notes/${a.id}'] =
        good.sublist(0, 12 + AttachmentCipher.defaultChunkSize + 28);
    await expectLater(fresh.read(a), throwsA(isA<AttachmentCorrupt>()));

    final flipped = Uint8List.fromList(good)..[100] ^= 1;
    server.files['u1/notes/${a.id}'] = flipped;
    await expectLater(fresh.read(a), throwsA(isA<AttachmentCorrupt>()));
  });

  test('too large is refused before anything is stored', () async {
    await expectLater(
        attachments.put(bytes(1000001)), throwsA(isA<AttachmentTooLarge>()));
    expect(cache.files, isEmpty);
  });

  test('never uploaded: a clear error on other devices', () async {
    final ref = await attachments.put(bytes(5));
    server.files.clear();
    final other = onDevice(InMemoryAttachmentCache());
    await expectLater(other.read(ref), throwsA(isA<AttachmentNotFound>()));
    expect(ztErrorMessage(const AttachmentNotFound('x')),
        contains('once the device that added it is back online'));
  });

  test('many puts and deletes at once lose no queue entry', () async {
    server.failWith = Exception('offline');
    final refs = await Future.wait([
      for (var i = 0; i < 20; i++) attachments.put(bytes(10 + i)),
    ]);
    await Future.wait([
      attachments.delete(refs[0]),
      attachments.delete(refs[1]),
      for (var i = 0; i < 5; i++) attachments.put(bytes(5)),
    ]);
    await pumpEventQueue();
    expect(await attachments.pendingUploadCount(), 23);
    server.failWith = null;
    await attachments.flush();
    expect(server.files, hasLength(23));
    expect(cache.uploads, isEmpty);
    expect(cache.deletes, isEmpty);
  });

  test('a new account after sign-out gets its own attachments', () async {
    final backend = _SwitchingAccount();
    final c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes')),
      accountServiceProvider.overrideWithValue(AccountService(backend)),
      ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
      ztAttachmentBackendProvider.overrideWithValue(server),
      ztAttachmentCacheProvider
          .overrideWith((ref) async => InMemoryAttachmentCache()),
      // No sync in this test.
      ztSyncControllerProvider.overrideWith(_IdleSync.new),
    ]);
    addTearDown(c.dispose);
    final vault = c.read(vaultControllerProvider.notifier);
    c.listen(ztAttachmentsProvider, (_, __) {});

    await vault.unlock(Uint8List(32));
    expect((await c.read(ztAttachmentsProvider.future)).userId, 'first');
    vault.lock();
    backend.user = 'second';
    await vault.unlock(Uint8List(32));
    final second = await c.read(ztAttachmentsProvider.future);
    expect(second.userId, 'second');
    expect(second.pathOf('x'), 'second/notes/x');
  });
}

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus();
}

class _SwitchingAccount implements AccountBackend {
  String user = 'first';
  @override
  String? get currentUserId => user;
  @override
  String? get currentEmail => '$user@x.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
