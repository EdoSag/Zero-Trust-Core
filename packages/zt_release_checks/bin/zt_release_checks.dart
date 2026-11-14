import 'dart:io';

import 'package:args/args.dart';
import 'package:zt_release_checks/zt_release_checks.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('app', help: "The app's ZtAppConfig.appId, e.g. notes.")
    ..addFlag('database',
        help: 'Also build the database from the pinned core on the Postgres '
            'that PGHOST/PGUSER/PGPASSWORD point at (a throwaway one), and '
            'check every table and function the app calls.',
        negatable: false)
    ..addFlag('flutter-tests',
        help: 'Run the key, sync and sign-in checks inside the app.',
        defaultsTo: true)
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);
  final appId = args['app'] as String?;
  if (args['help'] == true || appId == null) {
    stdout
      ..writeln('Usage: dart run zt_release_checks --app <appId> [options]')
      ..writeln(parser.usage);
    exit(appId == null && args['help'] != true ? 64 : 0);
  }
  final ok = await runReleaseChecks(
    Directory.current,
    appId: appId,
    database: args['database'] as bool,
    flutterTests: args['flutter-tests'] as bool,
  );
  exit(ok ? 0 : 1);
}
