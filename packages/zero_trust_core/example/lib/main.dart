import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() => runApp(const MaterialApp(home: SmokeCheck()));

/// Opens the encrypted store on this platform and checks the basics.
Future<String> runSmokeCheck() async {
  final log = <String>[];
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final path = await ZtLocalStore.pathFor(appId: 'smoke', userId: 'check');
  await ZtLocalStore.deleteFiles(path);

  var store = await ZtLocalStore.open(appKey: key, path: path);
  await store.put(
    LocalItem(
      itemId: 'a',
      updatedAt: DateTime.utc(2026, 11, 11, 9, 30, 0, 123, 456),
      dirty: true,
      json: {'title': 'hello'},
    ),
  );
  await store.close();

  store = await ZtLocalStore.open(appKey: key, path: path);
  final a = await store.get('a');
  await store.close();
  final readBack =
      a?.json?['title'] == 'hello' &&
      a!.dirty &&
      a.updatedAt == DateTime.utc(2026, 11, 11, 9, 30, 0, 123, 456);
  log.add(readBack ? 'read back' : 'READ BACK WRONG: $a');

  var refused = false;
  try {
    final other = await ZtLocalStore.open(
      appKey: Uint8List.fromList(List.filled(32, 7)),
      path: path,
    );
    await other.close();
  } on LocalStoreUnreadable {
    refused = true;
  }
  log.add(refused ? 'wrong key refused' : 'WRONG KEY OPENED');

  // Only one holder at a time on the web (browser tabs share the store).
  var exclusive = true;
  if (kIsWeb) {
    final first = await ZtLocalStore.open(appKey: key, path: path);
    try {
      final second = await ZtLocalStore.open(appKey: key, path: path);
      await second.close();
      exclusive = false;
    } on LocalStoreInUse {
      exclusive = true;
    }
    await first.close();
    log.add(exclusive ? 'second opener refused' : 'OPENED TWICE');
  }
  await ZtLocalStore.deleteFiles(path);

  var cache = await DatabaseAttachmentCache.forAccount(
    appId: 'smoke',
    userId: 'check',
  );
  await cache.write('a' * 32, Uint8List.fromList([1, 2, 3]));
  await cache.setPendingUploads({'a' * 32});
  await cache.close();
  cache = await DatabaseAttachmentCache.forAccount(
    appId: 'smoke',
    userId: 'check',
  );
  final attachmentKept =
      (await cache.read('a' * 32))?.length == 3 &&
      (await cache.pendingUploads()).contains('a' * 32);
  await cache.close();
  await DatabaseAttachmentCache.deleteFor(appId: 'smoke', userId: 'check');
  log.add(attachmentKept ? 'attachment kept' : 'ATTACHMENT LOST');

  final ok = readBack && refused && exclusive && attachmentKept;
  return '${ok ? 'PASS' : 'FAIL'}: ${log.join(', ')}';
}

class SmokeCheck extends StatefulWidget {
  const SmokeCheck({super.key});

  @override
  State<SmokeCheck> createState() => _SmokeCheckState();
}

class _SmokeCheckState extends State<SmokeCheck> {
  String _result = 'Running…';

  @override
  void initState() {
    super.initState();
    runSmokeCheck().catchError((Object e) => 'FAIL: $e').then((r) {
      debugPrint(r);
      if (mounted) setState(() => _result = r);
      // On desktop CI runs the app headless: exit with the result.
      if (!kIsWeb && const bool.fromEnvironment('ZT_SMOKE_EXIT')) {
        exit(r.startsWith('PASS') ? 0 : 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: SelectableText(_result)));
}
