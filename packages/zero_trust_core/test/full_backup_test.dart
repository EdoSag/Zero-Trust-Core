import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';
import 'support/fake_sync_backend.dart';

/// S-5: one encrypted backup file with every app's data.
void main() {
  const backupPassword = 'long backup password';
  final dekA = Uint8List.fromList(List.generate(32, (i) => i));
  final dekB = Uint8List.fromList(List.generate(32, (i) => 100 + i));
  final at = DateTime.utc(2026, 10, 1, 9); // before the fake server's clock

  Future<AppItemCodec> codec(Uint8List dek, String app) async {
    final key = await KeyHierarchy.appKey(dek, app);
    return AppItemCodec(
        appId: app,
        appKey: key,
        signingKeys: await KeyHierarchy.signingKeys(key));
  }

  Future<void> put(FakeSyncBackend server, Uint8List dek, String app, String id,
      Map<String, Object?>? json,
      {DateTime? when}) async {
    final c = await codec(dek, app);
    final row = await c.seal(
        LocalItem(
            itemId: id,
            updatedAt: when ?? at,
            json: json,
            deleted: json == null),
        'dev-a');
    await server.pushAll(app, [row]);
  }

  Future<Map<String, Object?>?> read(
      FakeSyncBackend server, Uint8List dek, String app, String id) async {
    final rows = await server.fetch(app, {id});
    if (rows.isEmpty) return null;
    return (await codec(dek, app)).open(rows.single);
  }

  late FakeSyncBackend serverA;
  late InMemoryAttachmentBackend filesA;
  late ZtAttachmentRef photo;
  late Uint8List photoBytes;

  setUp(() async {
    serverA = FakeSyncBackend();
    filesA = InMemoryAttachmentBackend();
    await put(serverA, dekA, 'notes', 'n1', {'title': 'Groceries'});
    await put(serverA, dekA, 'notes', 'gone', null); // a tombstone
    await put(serverA, dekA, 'contacts', 'c1', {'name': 'Dana'});
    // A row this account didn't sign (another key): left out.
    await put(serverA, dekB, 'tasks', 'forged', {'t': 'x'});
    // A photo big enough to need three chunks.
    photoBytes = Uint8List.fromList(
        List.generate(2500 * 1000, (i) => (i * 7919) & 0xff));
    const id = '0123456789abcdef0123456789abcdef';
    final key = Kdf.randomBytes(32);
    await filesA.upload('user-a/notes/$id',
        await AttachmentCipher.encrypt(photoBytes, key: key, attachmentId: id));
    photo = ZtAttachmentRef(
        id: id, key: key, size: photoBytes.length, name: 'photo.jpg');
    await put(serverA, dekA, 'notes', 'n2', {
      'title': 'Trip',
      'images': [photo.toJson()],
    });
  });

  Future<ZtBackupFile> backUp() => ZtBackup.create(
        dek: dekA,
        password: backupPassword,
        backend: serverA,
        files: filesA,
        userId: 'user-a',
        sourceApp: 'notes',
        now: DateTime.utc(2026, 11, 23, 8),
        params: fast,
      );

  test('backs up every app, encrypted', () async {
    final backup = await backUp();
    expect(backup.fileName, 'zero-trust-backup-2026-11-23.ztbackup');
    expect(backup.unreadableItems, 1);
    expect(backup.contents.items.keys, unorderedEquals(['notes', 'contacts']));
    expect(backup.contents.itemCount, 3);
    expect(backup.contents.files.keys, ['notes/${photo.id}']);
    // Nothing readable in the file itself.
    final text = String.fromCharCodes(backup.bytes);
    expect(text, isNot(contains('Groceries')));
    expect(text, isNot(contains('Dana')));
    expect(ZtBackup.checkHeader(backup.bytes), DateTime.utc(2026, 11, 23, 8));

    final opened = await ZtBackup.open(backup.bytes, backupPassword);
    expect(opened.sourceApp, 'notes');
    expect(opened.createdAt, DateTime.utc(2026, 11, 23, 8));
    final notes = {for (final i in opened.items['notes']!) i.id: i};
    expect(notes.keys, unorderedEquals(['n1', 'n2']));
    expect(notes['n1']!.json, {'title': 'Groceries'});
    expect(notes['n1']!.updatedAt, at);
    expect(opened.items['contacts']!.single.json, {'name': 'Dana'});
    expect(opened.files['notes/${photo.id}'],
        await filesA.download('user-a/notes/${photo.id}'));
  });

  test('refuses short passwords', () async {
    expect(
        () => ZtBackup.create(
            dek: dekA,
            password: 'short',
            backend: serverA,
            sourceApp: 'notes',
            params: fast),
        throwsArgumentError);
  });

  test('tells a wrong password, another file and damage apart', () async {
    final backup = await backUp();
    await expectLater(ZtBackup.open(backup.bytes, 'not the password!'),
        throwsA(isA<WrongBackupPassword>()));
    await expectLater(
        ZtBackup.open(Uint8List.fromList('PK\x03\x04 a zip'.codeUnits), 'x'),
        throwsA(isA<NotABackup>()));
    expect(
        () => ZtBackup.checkHeader(Uint8List(3)), throwsA(isA<NotABackup>()));

    // Cut after a whole chunk: the new last chunk wasn't sealed as last.
    final cut =
        Uint8List.sublistView(backup.bytes, 0, _endOfChunk(backup.bytes, 1));
    await expectLater(
        ZtBackup.open(cut, backupPassword), throwsA(isA<BackupDamaged>()));
    // Cut in the middle of a chunk.
    await expectLater(
        ZtBackup.open(
            Uint8List.sublistView(backup.bytes, 0, backup.bytes.length - 10),
            backupPassword),
        throwsA(isA<BackupDamaged>()));
    // One byte changed.
    final flipped = Uint8List.fromList(backup.bytes);
    flipped[flipped.length - 100] ^= 1;
    await expectLater(
        ZtBackup.open(flipped, backupPassword), throwsA(isA<BackupDamaged>()));
    // The date in the header changed: every chunk is bound to it.
    final redated = Uint8List.fromList(backup.bytes);
    final i = String.fromCharCodes(redated).indexOf('2026-11-23');
    redated[i + 3] = '5'.codeUnitAt(0);
    await expectLater(
        ZtBackup.open(redated, backupPassword), throwsA(isA<BackupDamaged>()));
  });

  test('restores into a new account on another phone', () async {
    final backup = await backUp();
    final contents = await ZtBackup.open(backup.bytes, backupPassword);
    final serverB = FakeSyncBackend();
    final filesB = InMemoryAttachmentBackend();

    final result = await ZtBackup.restore(
      contents: contents,
      dek: dekB,
      backend: serverB,
      deviceId: 'dev-b',
      files: filesB,
      userId: 'user-b',
    );
    expect(result.restored, 3);
    expect(result.skipped, 0);
    expect(result.files, 1);

    // Sealed and signed under the new account's keys, dates kept.
    expect(await read(serverB, dekB, 'notes', 'n1'), {'title': 'Groceries'});
    expect(await read(serverB, dekB, 'contacts', 'c1'), {'name': 'Dana'});
    expect((await serverB.fetch('notes', {'n1'})).single.updatedAt, at);
    await expectLater(read(serverB, dekA, 'notes', 'n1'), throwsA(anything));
    // The photo opens with the key kept in the note.
    final note = (await read(serverB, dekB, 'notes', 'n2'))!;
    final ref = ZtAttachmentRef.fromJson(
        ((note['images']! as List).single as Map).cast<String, Object?>());
    final sealed = await filesB.download('user-b/notes/${ref.id}');
    expect(
        await AttachmentCipher.decrypt(sealed,
            key: ref.key, attachmentId: ref.id),
        photoBytes);
  });

  test('restoring into the same account keeps newer changes', () async {
    final backup = await backUp();
    final later = at.add(const Duration(days: 3));
    await put(serverA, dekA, 'notes', 'n1', {'title': 'Groceries (edited)'},
        when: later);
    await put(serverA, dekA, 'contacts', 'c1', null, when: later);

    final result = await ZtBackup.restore(
      contents: await ZtBackup.open(backup.bytes, backupPassword),
      dek: dekA,
      backend: serverA,
      deviceId: 'dev-a',
    );
    expect(result.skipped, greaterThanOrEqualTo(2));
    expect(await read(serverA, dekA, 'notes', 'n1'),
        {'title': 'Groceries (edited)'});
    expect(await read(serverA, dekA, 'contacts', 'c1'), isNull);
    expect(await read(serverA, dekA, 'notes', 'n2'), isNotNull);
  });

  group('settings', () {
    const email = 'edo@example.com';
    const password = 'correct horse battery';

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<AccountService> signedIn() async {
      final account =
          AccountService(FakeBackend(), params: fast, legacyParams: fast);
      await account.signUp(email: email, password: password);
      return account;
    }

    Widget app(AccountService account, {ZtBackupFiles? files}) => ProviderScope(
          overrides: [
            accountServiceProvider.overrideWithValue(account),
            ztPreferencesStoreProvider
                .overrideWithValue(InMemoryPreferencesStore()),
            ztAppConfigProvider.overrideWithValue(const ZtAppConfig(
                appId: 'notes', displayName: 'Zero-Trust Notes')),
            ztSyncBackendProvider.overrideWithValue(serverA),
            ztAttachmentBackendProvider.overrideWithValue(filesA),
            ztDeviceIdStoreProvider.overrideWithValue(InMemoryDeviceIdStore()),
            ztBackupFilesProvider.overrideWithValue(files),
          ],
          child: MaterialApp(
            theme: ZtTheme.light(),
            localizationsDelegates: ZtLanguages.delegates,
            supportedLocales: ZtL10n.supportedLocales,
            home: ZtSettingsPage(onSignedOut: () {}),
          ),
        );

    testWidgets('hidden until the app gives a way to save files',
        (tester) async {
      await tester
          .pumpWidget(app(await tester.runAsync(signedIn) as AccountService));
      await settle(tester);
      expect(find.text('Back up everything'), findsNothing);
    });

    testWidgets('backs up, then restores the file', (tester) async {
      final account = (await tester.runAsync(signedIn))!;
      Uint8List? saved;
      String? savedName;
      await tester.pumpWidget(app(account,
          files: ZtBackupFiles(
            save: (name, bytes) async {
              savedName = name;
              saved = bytes;
              return true;
            },
            pick: () async => saved,
          )));
      await settle(tester);

      await tester.scrollUntilVisible(find.text('Back up everything'), 100);
      final backup = tester.getRect(find.byKey(const Key('zt-backup')));
      final restore = tester.getRect(find.byKey(const Key('zt-restore')));
      expect(restore.top, greaterThanOrEqualTo(backup.bottom - 0.01));
      await tester.tap(find.text('Back up everything'));
      await tester.pumpAndSettle();

      // Too short, then not matching.
      await tester.enterText(
          find.byKey(const Key('zt-backup-password')), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
      await tester.pump();
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('zt-backup-password')), backupPassword);
      await tester.enterText(
          find.byKey(const Key('zt-backup-password-repeat')), 'something else');
      await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
      await tester.pump();
      expect(find.text("Passwords don't match."), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('zt-backup-password-repeat')), backupPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
      await tester.pumpAndSettle();

      // The account password, to read every app's data.
      expect(
          find.text(
              'Enter your account password to read your data from every app.'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
      await waitFor(tester, () => saved != null);
      expect(savedName, endsWith('.ztbackup'));
      // This account's DEK is not dekA, so the seeded rows don't open: the
      // backup is just empty, which is what an account without data gets.
      expect(find.textContaining('Backup saved: 0 items from 0 apps.'),
          findsOneWidget);

      // Restore it: wrong backup password first.
      await tester.pumpAndSettle(const Duration(seconds: 10));
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('zt-open-backup-password')), 'wrong password!!');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await waitFor(tester,
          () => find.text('Wrong backup password.').evaluate().isNotEmpty);
      expect(find.text('Wrong backup password.'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('zt-open-backup-password')), backupPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await waitFor(tester,
          () => find.text('Restore this backup?').evaluate().isNotEmpty);
      expect(find.text('Restore this backup?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, password);
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await waitFor(
          tester, () => find.textContaining('Restored').evaluate().isNotEmpty);
      expect(find.textContaining('Restored 0 items.'), findsOneWidget);
    });
  });
}

/// Where chunk [n] (counting from 0) of a backup ends.
int _endOfChunk(Uint8List bytes, int n) {
  final headerLength = ByteData.sublistView(bytes, 9, 13).getUint32(0);
  var at = 13 + headerLength;
  for (var i = 0; i <= n; i++) {
    at += 4 + ByteData.sublistView(bytes, at, at + 4).getUint32(0);
  }
  return at;
}
