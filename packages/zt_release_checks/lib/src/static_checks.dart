import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The outcome of one check.
class CheckResult {
  const CheckResult(this.name, this.problems);

  final String name;

  /// Empty when the check passed. Each line says what to fix.
  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// The Zero-Trust-Core packages an app can depend on. All must come from the
/// same commit, or the app builds against two different cores.
const corePackages = {
  'zero_trust_core',
  'zt_crypto',
  'zt_sharing_ui',
  'zt_places',
};

/// Every app id in the suite (the `ZtAppConfig.appId` values).
const suiteAppIds = {
  'notes',
  'tasks',
  'fitness',
  'contacts',
  'calendar',
  'phone',
  'browser',
  'time',
  'meds',
};

/// Checks that need no device and no network: what went wrong in past
/// releases, or would lock users out if it slipped in.
List<CheckResult> runStaticChecks(Directory app, {required String appId}) {
  final pubspec = _yaml(File(p.join(app.path, 'pubspec.yaml')));
  final lockFile = File(p.join(app.path, 'pubspec.lock'));
  final lock = lockFile.existsSync() ? _yaml(lockFile) : null;
  final lockPackages = (lock?['packages'] as Map?) ?? const {};

  return [
    CheckResult('app id', [
      if (!suiteAppIds.contains(appId))
        '"$appId" is not a suite app id (${suiteAppIds.join(', ')}).',
      if (!_libMentionsAppId(app, appId))
        "No ZtAppConfig with appId: '$appId' found under lib/.",
    ]),
    CheckResult('pubspec version', [
      if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$')
          .hasMatch('${pubspec['version'] ?? ''}'))
        'pubspec.yaml version must look like 1.2.3+4 '
            '(found "${pubspec['version']}").',
    ]),
    CheckResult('no cryptography_flutter', [
      if (lock == null)
        'pubspec.lock is missing; run flutter pub get first.'
      else if (lockPackages.containsKey('cryptography_flutter'))
        'cryptography_flutter is in pubspec.lock. It swaps in Android '
            'crypto that breaks HKDF and stops sign-in (2026-11-09). '
            'Remove whatever pulls it in.',
    ]),
    CheckResult('core pinned to a fixed commit', _corePinProblems(pubspec)),
    CheckResult(
        'core packages from one commit', _sameCommitProblems(lockPackages)),
    CheckResult('encrypted local database', [
      if (_sqliteSource(pubspec) != 'sqlite3mc')
        'pubspec.yaml needs hooks: user_defines: sqlite3: source: sqlite3mc, '
            'or the local store is not encrypted.',
    ]),
    CheckResult('internet permission', _internetProblems(app)),
    CheckResult('no secrets in git', _secretProblems(app)),
  ];
}

YamlMap _yaml(File f) => loadYaml(f.readAsStringSync()) as YamlMap;

bool _libMentionsAppId(Directory app, String appId) {
  final lib = Directory(p.join(app.path, 'lib'));
  if (!lib.existsSync()) return false;
  final pattern = RegExp(
      "ZtAppConfig\\s*\\([^;]*?appId:\\s*['\"]${RegExp.escape(appId)}['\"]",
      dotAll: true);
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.dart') && pattern.hasMatch(f.readAsStringSync())) {
      return true;
    }
  }
  return false;
}

final _fullSha = RegExp(r'^[0-9a-f]{40}$');
final _versionTag = RegExp(r'^v\d+\.\d+\.\d+$');

List<String> _corePinProblems(YamlMap pubspec) {
  final deps = (pubspec['dependencies'] as Map?) ?? const {};
  final problems = <String>[];
  for (final name in corePackages) {
    final dep = deps[name];
    if (dep == null) continue;
    final git = dep is Map ? dep['git'] : null;
    final ref = git is Map ? '${git['ref'] ?? ''}' : '';
    if (git == null) {
      problems.add('$name must be a git dependency on Zero-Trust-Core.');
    } else if (!_fullSha.hasMatch(ref) && !_versionTag.hasMatch(ref)) {
      problems.add('$name ref "$ref" can move. Pin a full commit SHA or a '
          'release tag (v1.2.3) so a release builds the core it was tested '
          'with.');
    }
  }
  if (!deps.containsKey('zero_trust_core')) {
    problems.add('zero_trust_core is not a dependency.');
  }
  return problems;
}

List<String> _sameCommitProblems(Map lockPackages) {
  final refs = <String, String>{};
  for (final name in corePackages) {
    final entry = lockPackages[name];
    if (entry is! Map || entry['source'] != 'git') continue;
    refs[name] = '${(entry['description'] as Map)['resolved-ref']}';
  }
  if (refs.values.toSet().length <= 1) return const [];
  return [
    'Core packages resolve to different commits: '
        '${refs.entries.map((e) => '${e.key} ${e.value.length > 7 ? e.value.substring(0, 7) : e.value}').join(', ')}. '
        'Pin them all to the same ref.',
  ];
}

String? _sqliteSource(YamlMap pubspec) {
  final hooks = pubspec['hooks'];
  if (hooks is! Map) return null;
  final defines = hooks['user_defines'];
  if (defines is! Map) return null;
  final sqlite = defines['sqlite3'];
  return sqlite is Map ? '${sqlite['source']}' : null;
}

List<String> _internetProblems(Directory app) {
  final manifest =
      File(p.join(app.path, 'android/app/src/main/AndroidManifest.xml'));
  if (!manifest.existsSync()) {
    return ['android/app/src/main/AndroidManifest.xml is missing.'];
  }
  if (manifest.readAsStringSync().contains('android.permission.INTERNET')) {
    return const [];
  }
  return [
    'The main AndroidManifest.xml has no INTERNET permission. Debug builds '
        'add it, release builds do not, so the released app cannot reach '
        'the server (Notes, 2026-11-09).',
  ];
}

List<String> _secretProblems(Directory app) {
  final tracked = _gitFiles(app);
  if (tracked == null) return const [];
  final problems = <String>[];
  for (final f in tracked) {
    final name = p.basename(f);
    if (name == '.env' ||
        (name.startsWith('.env.') && name != '.env.example')) {
      problems.add('$f is committed. Keep it out of git (CI writes it).');
    } else if (name.endsWith('.jks') ||
        name.endsWith('.keystore') ||
        name == 'key.properties') {
      problems.add('$f is committed. Signing keys belong in CI secrets.');
    }
  }
  for (final f in tracked.where((f) =>
      f.endsWith('.dart') ||
      f.endsWith('.yaml') ||
      f.endsWith('.json') ||
      f.endsWith('.xml') ||
      f.endsWith('.kts') ||
      f.endsWith('.gradle'))) {
    final file = File(p.join(app.path, f));
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    if (text.contains('service_role') || text.contains('sb_secret_')) {
      problems.add('$f mentions a Supabase secret key (service_role / '
          'sb_secret_). Apps only ever ship the publishable key.');
    }
  }
  return problems;
}

List<String>? _gitFiles(Directory app) {
  try {
    final r = Process.runSync('git', ['ls-files'], workingDirectory: app.path);
    if (r.exitCode != 0) return null;
    return '${r.stdout}'.split('\n').where((l) => l.isNotEmpty).toList();
  } on ProcessException {
    return null;
  }
}
