import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'static_checks.dart';

/// A table or function the app's own code calls, outside the core.
class DbUse {
  const DbUse(this.kind, this.name, this.file);

  /// `table` (`.from('x')`) or `function` (`.rpc('x')`).
  final String kind;
  final String name;

  /// Path relative to the app.
  final String file;
}

final _fromCall = RegExp(r"""\.from\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]""");
final _rpcCall = RegExp(r"""\.rpc\(\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]""");

/// Tables and functions the app reaches directly through Supabase. Storage
/// buckets (`client.storage.from('bucket')`) are skipped.
List<DbUse> findDbUses(Directory app) {
  final lib = Directory(p.join(app.path, 'lib'));
  if (!lib.existsSync()) return const [];
  final uses = <DbUse>[];
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final text = f.readAsStringSync();
    final rel = p.relative(f.path, from: app.path);
    for (final m in _fromCall.allMatches(text)) {
      if (_isStorage(text, m.start)) continue;
      uses.add(DbUse('table', m.group(1)!, rel));
    }
    for (final m in _rpcCall.allMatches(text)) {
      uses.add(DbUse('function', m.group(1)!, rel));
    }
  }
  return uses;
}

/// True when the `.from(` at [at] continues a `storage` chain.
bool _isStorage(String text, int at) {
  final before = text.substring(0, at).trimRight();
  return before.endsWith('storage') || before.endsWith('storage)');
}

/// Where the app's pinned Zero-Trust-Core checkout lives: pub keeps one per
/// commit, and `.dart_tool/package_config.json` points into it.
Directory? pinnedCoreRepo(Directory app) {
  final config = File(p.join(app.path, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return null;
  final json = jsonDecode(config.readAsStringSync()) as Map;
  for (final pkg in (json['packages'] as List).cast<Map>()) {
    if (pkg['name'] != 'zero_trust_core') continue;
    var root = Uri.parse('${pkg['rootUri']}');
    if (!root.isAbsolute) {
      root = Uri.file(p.join(p.dirname(config.path), root.toFilePath()));
    }
    // .../packages/zero_trust_core -> repository root
    return Directory(p.normalize(p.join(root.toFilePath(), '..', '..')));
  }
  return null;
}

/// The SQL that builds the shared database: the Supabase stand-in and every
/// migration in order, then core's own database tests (row level security,
/// key guards, quotas, sharing), each meant for a fresh copy. Returns null
/// when the checkout has none.
({List<File> setup, List<File> tests})? databaseScripts(Directory coreRepo) {
  final migrations = Directory(p.join(coreRepo.path, 'supabase', 'migrations'));
  final tests = Directory(p.join(coreRepo.path, 'supabase', 'tests'));
  final stub = File(p.join(tests.path, '00_supabase_stub.sql'));
  if (!migrations.existsSync() || !stub.existsSync()) return null;
  List<File> sql(Directory d) => d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return (
    setup: [stub, ...sql(migrations)],
    tests: [
      ...sql(tests).where((f) => p.basename(f.path) != '00_supabase_stub.sql'),
    ],
  );
}

/// Tables the migrations drop: the pre-core data the old apps wrote.
Set<String> droppedTables(Directory coreRepo) {
  final dropped = <String>{};
  final pattern = RegExp(
      r'drop\s+table\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)',
      caseSensitive: false);
  final dir = Directory(p.join(coreRepo.path, 'supabase', 'migrations'));
  for (final f in dir.listSync().whereType<File>()) {
    for (final m in pattern.allMatches(f.readAsStringSync())) {
      dropped.add(m.group(1)!.toLowerCase());
    }
  }
  return dropped;
}

/// Builds the database from the app's pinned core on the Postgres that the
/// standard PG* variables point at (an empty, throwaway one: CI uses a
/// service container), runs core's database tests there, then checks that
/// every table and function the app calls exists and is guarded.
Future<List<CheckResult>> runDatabaseChecks(Directory app) async {
  final core = pinnedCoreRepo(app);
  if (core == null) {
    return [
      const CheckResult('database', [
        'No zero_trust_core in .dart_tool/package_config.json; run '
            'flutter pub get first.',
      ]),
    ];
  }
  final scripts = databaseScripts(core);
  if (scripts == null) {
    return [
      CheckResult('database', ['No supabase/ folder in ${core.path}.']),
    ];
  }

  // A base database with every migration, then one fresh copy per test
  // file, since core's test files each expect a clean start.
  const base = 'zt_release_base', scratch = 'zt_release_test';
  final problems0 = <String>[];
  Future<bool> step(String what, List<String> args, {String? db}) async {
    final r = await _psql(args, database: db);
    if (r.exitCode != 0) problems0.add('$what failed:\n${_tail(r.stderr)}');
    return r.exitCode == 0;
  }

  if (await step('Creating a scratch database', [
        '-c',
        'drop database if exists $base',
        '-c',
        'create database $base'
      ]) &&
      await step(
          'Applying the core migrations',
          [
            for (final f in scripts.setup) ...['-f', f.path]
          ],
          db: base)) {
    for (final test in scripts.tests) {
      await step('Database test ${p.basename(test.path)}', [
        '-c',
        'drop database if exists $scratch',
        '-c',
        'create database $scratch template $base',
      ]);
      await step('Database test ${p.basename(test.path)}', ['-f', test.path],
          db: scratch);
    }
  }
  final results = <CheckResult>[
    CheckResult(
        'database rules of the pinned core (${scripts.tests.length} test files)',
        problems0),
  ];
  if (problems0.isNotEmpty) return results;

  final uses = findDbUses(app);
  final dropped = droppedTables(core);
  final problems = <String>[];
  final legacyProblems = <String>[];
  for (final use in uses) {
    if (use.kind == 'table' && dropped.contains(use.name)) {
      // Pre-core tables are gone. The import code must read "missing" as
      // "nothing to import", or old users get an error instead of their app.
      final text = File(p.join(app.path, use.file)).readAsStringSync();
      if (!text.contains('PGRST205') && !text.contains('42P01')) {
        legacyProblems.add('${use.file} reads ${use.name}, which the '
            'migrations drop, but never handles a missing table '
            '(PGRST205 / 42P01).');
      }
      continue;
    }
    final query = use.kind == 'table'
        ? "select coalesce((select c.relrowsecurity or c.relkind = 'v' "
            "from pg_class c where c.oid = to_regclass('public.${use.name}')), "
            "null)::text"
        : "select exists(select 1 from pg_proc p join pg_namespace n on "
            "n.oid = p.pronamespace where n.nspname = 'public' and "
            "p.proname = '${use.name}' and has_function_privilege("
            "'authenticated', p.oid, 'execute'))::text";
    final r = await _psql(['-tAc', query], database: base);
    final answer = '${r.stdout}'.trim();
    if (r.exitCode != 0) {
      problems.add('${use.file}: checking ${use.name} failed: ${r.stderr}');
    } else if (use.kind == 'table' && answer.isEmpty) {
      problems.add('${use.file} uses table ${use.name}, which no core '
          'migration creates.');
    } else if (use.kind == 'table' && answer != 'true') {
      problems.add('${use.file} uses table ${use.name}, which has no row '
          'level security.');
    } else if (use.kind == 'function' && answer != 'true') {
      problems.add('${use.file} calls ${use.name}(), which no core migration '
          'creates for signed-in users.');
    }
  }
  results
    ..add(CheckResult(
        'tables and functions the app calls (${uses.length} uses)', problems))
    ..add(CheckResult('old tables handled as gone', legacyProblems));
  await _psql([
    '-c',
    'drop database if exists $scratch',
    '-c',
    'drop database if exists $base',
  ]);
  return results;
}

Future<ProcessResult> _psql(List<String> args, {String? database}) =>
    Process.run(
      'psql',
      [
        '-q',
        '-X',
        '-v',
        'ON_ERROR_STOP=1',
        if (database != null) ...['-d', database],
        ...args,
      ],
      environment: {'PGOPTIONS': '-c client_min_messages=warning'},
    );

String _tail(Object? text, [int lines = 15]) {
  final all = '$text'.trimRight().split('\n');
  return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
}
