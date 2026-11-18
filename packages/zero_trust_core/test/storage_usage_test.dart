import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

class _FakeUsage implements StorageUsageSource {
  _FakeUsage(this.usage);
  final ZtStorageUsage? usage;
  @override
  Future<ZtStorageUsage?> fetch() async => usage;
}

void main() {
  test('usage parses the zt_my_storage JSON', () {
    final u = ZtStorageUsage.fromJson({
      'item_bytes': 2500000,
      'item_count': 527,
      'attachment_bytes': 0,
      'max_blob_bytes': 1048576,
      'max_item_bytes': 52428800,
      'max_items': 100000,
      'max_attachment_bytes': 524288000,
    });
    expect(u.itemCount, 527);
    expect(u.fraction, closeTo(2500000 / 52428800, 1e-9));
  });

  test('the fuller limit decides the fraction, capped at 1', () {
    const u = ZtStorageUsage(
      itemBytes: 10,
      itemCount: 150,
      attachmentBytes: 0,
      maxBlobBytes: 1,
      maxItemBytes: 1000,
      maxItems: 100,
      maxAttachmentBytes: 1,
    );
    expect(u.fraction, 1);
  });

  test('bytes are formatted in decimal units', () {
    expect(formatBytes(999), '999 B');
    expect(formatBytes(2400000), '2.4 MB');
    expect(formatBytes(52428800), '52.4 MB');
    expect(formatBytes(524288000), '524 MB');
    expect(formatBytes(1000000000), '1 GB');
  });

  Widget app(ZtStorageUsage? usage) => ProviderScope(
        overrides: [
          ztStorageUsageSourceProvider.overrideWithValue(_FakeUsage(usage)),
        ],
        child: MaterialApp(
          theme: ZtTheme.light(),
          home: const Scaffold(body: ZtStorageTile()),
        ),
      );

  testWidgets('the storage row shows usage and attachments', (tester) async {
    await tester.pumpWidget(app(const ZtStorageUsage(
      itemBytes: 2400000,
      itemCount: 10,
      attachmentBytes: 12000000,
      maxBlobBytes: 1048576,
      maxItemBytes: 50000000,
      maxItems: 100000,
      maxAttachmentBytes: 500000000,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('2.4 MB of 50 MB used'), findsOneWidget);
    expect(find.text('Attachments: 12 MB of 500 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  test('the Unlimited plan has no limit', () {
    // What zt_my_storage() returns for it: 2^53 - 1 everywhere.
    final u = ZtStorageUsage.fromJson({
      'item_bytes': 2500000,
      'item_count': 527,
      'attachment_bytes': 12000000,
      'max_blob_bytes': 1048576,
      'max_item_bytes': 9007199254740991,
      'max_items': 9007199254740991,
      'max_attachment_bytes': 9007199254740991,
    });
    expect(u.itemsUnlimited, isTrue);
    expect(u.attachmentsUnlimited, isTrue);
    expect(u.fraction, lessThan(0.000001));

    // Plus (1 GiB, 20 GiB) is a real limit.
    const plus = ZtStorageUsage(
      itemBytes: 0,
      itemCount: 0,
      attachmentBytes: 0,
      maxBlobBytes: 1048576,
      maxItemBytes: 1073741824,
      maxItems: 1000000,
      maxAttachmentBytes: 21474836480,
    );
    expect(plus.itemsUnlimited, isFalse);
    expect(plus.attachmentsUnlimited, isFalse);
  });

  testWidgets('no limit: usage without a limit or a bar', (tester) async {
    await tester.pumpWidget(app(const ZtStorageUsage(
      itemBytes: 2400000,
      itemCount: 10,
      attachmentBytes: 12000000,
      maxBlobBytes: 1048576,
      maxItemBytes: 9007199254740991,
      maxItems: 9007199254740991,
      maxAttachmentBytes: 9007199254740991,
    )));
    await tester.pumpAndSettle();
    expect(find.text('2.4 MB used, no limit'), findsOneWidget);
    expect(find.text('Attachments: 12 MB, no limit'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining(' of '), findsNothing);
  });

  testWidgets('signed out: no row', (tester) async {
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    expect(find.text('Storage'), findsNothing);
  });

  test('sync status carries storage full and too-large items', () async {
    SyncStatus? last;
    final scheduler = SyncScheduler(
      sync: () async => const SyncResult(storageFull: true, tooLarge: ['big']),
      onStatus: (s) => last = s,
    );
    await scheduler.syncNow();
    scheduler.dispose();
    expect(last!.storageFull, isTrue);
    expect(last!.tooLarge, ['big']);
  });
}
