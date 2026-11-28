import 'dart:io';

import 'package:zt_release_checks/zt_release_checks.dart';

/// `dart run zt_release_checks:zt_tracker_check <apk or aab> [...]`, from
/// the app folder, after the release build.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.any((a) => a == '-h' || a == '--help')) {
    stdout
      ..writeln('Usage: dart run zt_release_checks:zt_tracker_check '
          '<app.apk or app.aab> [more files]')
      ..writeln('Fails when the code in any of the files has names from '
          "Exodus Privacy's list of known trackers.");
    exit(arguments.isEmpty ? 64 : 0);
  }
  exit(await runTrackerCheck(arguments) ? 0 : 1);
}
