import 'dart:typed_data';

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

  await ZtLocalStore.deleteFiles(path);
  final ok = readBack && refused;
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
    });
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: SelectableText(_result)));
}
