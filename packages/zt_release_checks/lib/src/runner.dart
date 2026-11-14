import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'database_checks.dart';
import 'static_checks.dart';

/// Name of the temporary test file the Flutter checks run from. Apps add it
/// to .gitignore so a stopped run never leaves it committed.
const flutterTestFile = 'test/zt_release_checks_test.dart';

/// Runs every check, prints a report, and returns whether all passed.
Future<bool> runReleaseChecks(
  Directory app, {
  required String appId,
  bool database = false,
  bool flutterTests = true,
}) async {
  final results = [
    ...runStaticChecks(app, appId: appId),
    if (database) ...await runDatabaseChecks(app),
  ];
  var ok = _report(results);

  if (flutterTests) {
    stdout.writeln('\nKeys, sync and sign-in, inside the app:');
    final passed = await runFlutterChecks(app, appId: appId);
    stdout.writeln(passed ? 'PASS  flutter checks' : 'FAIL  flutter checks');
    ok = ok && passed;
  }
  stdout.writeln(ok
      ? '\nAll release checks passed.'
      : '\nRelease checks failed. Fix the items marked FAIL before releasing.');
  return ok;
}

bool _report(List<CheckResult> results) {
  for (final r in results) {
    stdout.writeln('${r.ok ? 'PASS' : 'FAIL'}  ${r.name}');
    for (final problem in r.problems) {
      stdout.writeln('      - $problem');
    }
  }
  return results.every((r) => r.ok);
}

/// Copies templates/release_checks_test.dart into the app, runs it with the
/// app's own dependencies (so a dependency the app pulls in, or its core pin,
/// is what gets tested), and removes it again.
Future<bool> runFlutterChecks(Directory app, {required String appId}) async {
  final template = await _templateFile();
  final target = File(p.join(app.path, flutterTestFile));
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(
      template.readAsStringSync().replaceAll('{{APP_ID}}', appId));
  try {
    final process = await Process.start(
      'flutter',
      ['test', flutterTestFile],
      workingDirectory: app.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    return await process.exitCode == 0;
  } finally {
    if (target.existsSync()) target.deleteSync();
  }
}

Future<File> _templateFile() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:zt_release_checks/zt_release_checks.dart'));
  final root = p.dirname(p.dirname(lib!.toFilePath()));
  return File(p.join(root, 'templates', 'release_checks_test.dart'));
}
