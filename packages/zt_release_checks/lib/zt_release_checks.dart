/// Release checks shared by every Zero-Trust app. Run from the app folder:
/// `dart run zt_release_checks --app <appId> [--database]`.
library;

export 'src/database_checks.dart';
export 'src/runner.dart';
export 'src/static_checks.dart';
