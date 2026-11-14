import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zt_release_checks/zt_release_checks.dart';

const _sha = 'cb397d13efd868e34a34d465251a7f705b49f9e1';

/// A small app folder that passes every static check; tests break one thing.
Directory _goodApp({
  String coreRef = _sha,
  String sqliteSource = 'sqlite3mc',
  bool internet = true,
  String extraLock = '',
  String sharingRef = _sha,
}) {
  final dir = Directory.systemTemp.createTempSync('zt_rc_');
  void write(String path, String text) {
    final f = File(p.join(dir.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  write('pubspec.yaml', '''
name: some_app
version: 1.2.3+4
dependencies:
  zero_trust_core:
    git:
      url: https://github.com/EdoSag/Zero-Trust-Core.git
      path: packages/zero_trust_core
      ref: $coreRef
hooks:
  user_defines:
    sqlite3:
      source: $sqliteSource
''');
  write('pubspec.lock', '''
packages:
  zero_trust_core:
    dependency: "direct main"
    description:
      path: "packages/zero_trust_core"
      ref: $coreRef
      resolved-ref: $_sha
      url: "https://github.com/EdoSag/Zero-Trust-Core.git"
    source: git
    version: "0.11.0"
  zt_sharing_ui:
    dependency: "direct main"
    description:
      path: "packages/zt_sharing_ui"
      ref: $sharingRef
      resolved-ref: $sharingRef
      url: "https://github.com/EdoSag/Zero-Trust-Core.git"
    source: git
    version: "0.1.0"
$extraLock''');
  write('lib/main.dart', '''
const config = ZtAppConfig(
  appId: 'notes',
  displayName: 'Zero-Trust Notes',
);
''');
  write('android/app/src/main/AndroidManifest.xml', '''
<manifest>
  ${internet ? '<uses-permission android:name="android.permission.INTERNET"/>' : ''}
</manifest>
''');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Map<String, List<String>> _failures(Directory app, {String appId = 'notes'}) =>
    {
      for (final r in runStaticChecks(app, appId: appId))
        if (!r.ok) r.name: r.problems,
    };

void main() {
  test('a well set up app passes', () {
    expect(_failures(_goodApp()), isEmpty);
  });

  test('a release tag is an accepted pin', () {
    expect(_failures(_goodApp(coreRef: 'v0.11.0')), isEmpty);
  });

  test('a branch pin fails', () {
    expect(_failures(_goodApp(coreRef: 'Dev')).keys,
        contains('core pinned to a fixed commit'));
  });

  test('core packages from two commits fail', () {
    expect(
        _failures(_goodApp(
                sharingRef: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'))
            .keys,
        contains('core packages from one commit'));
  });

  test('cryptography_flutter anywhere in the lock fails', () {
    final app = _goodApp(extraLock: '''
  cryptography_flutter:
    dependency: transitive
    source: hosted
    version: "2.3.2"
''');
    expect(_failures(app).keys, ['no cryptography_flutter']);
  });

  test('an unencrypted local database fails', () {
    expect(_failures(_goodApp(sqliteSource: 'sqlite3')).keys,
        ['encrypted local database']);
  });

  test('a release manifest without INTERNET fails', () {
    expect(_failures(_goodApp(internet: false)).keys, ['internet permission']);
  });

  test('a wrong or unknown app id fails', () {
    expect(_failures(_goodApp(), appId: 'tasks').keys, ['app id']);
    expect(_failures(_goodApp(), appId: 'mail').keys, ['app id']);
  });

  group('database uses', () {
    test('finds tables and functions, skips storage buckets', () {
      final app = _goodApp();
      File(p.join(app.path, 'lib/api.dart')).writeAsStringSync('''
final a = client.from('zt_bookings').select();
final b = client
    .from("zt_booking_pages")
    .upsert(row);
final c = client.storage.from('attachments').upload(path, file);
final d = client.storage
    .from('photos');
final e = client.rpc('zt_storage_usage');
final f = List.from(items);
''');
      final uses = findDbUses(app);
      expect(uses.map((u) => '${u.kind}:${u.name}'), [
        'table:zt_bookings',
        'table:zt_booking_pages',
        'function:zt_storage_usage',
      ]);
    });

    test('the pinned core is found through package_config.json', () {
      final app = _goodApp();
      final core = Directory(p.join(app.path, 'cache', 'Zero-Trust-Core-x'));
      File(p.join(core.path, 'packages', 'zero_trust_core', 'pubspec.yaml'))
          .createSync(recursive: true);
      File(p.join(app.path, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"packages": [{"name": "zero_trust_core", '
            '"rootUri": "${Uri.directory(p.join(core.path, 'packages', 'zero_trust_core'))}"}]}');
      expect(p.equals(pinnedCoreRepo(app)!.path, core.path), isTrue);
    });

    test('dropped tables are read from the migrations', () {
      final core = Directory.systemTemp.createTempSync('zt_core_');
      addTearDown(() => core.deleteSync(recursive: true));
      File(p.join(core.path, 'supabase', 'migrations', '1_drop.sql'))
        ..createSync(recursive: true)
        ..writeAsStringSync('drop table if exists public.encrypted_notes;\n'
            'DROP TABLE encrypted_tasks;');
      expect(droppedTables(core), {'encrypted_notes', 'encrypted_tasks'});
    });
  });

  test('the Flutter template covers every suite app', () {
    final template =
        File('templates/release_checks_test.dart').readAsStringSync();
    for (final app in suiteAppIds) {
      expect(RegExp("^  '$app': \\(", multiLine: true).allMatches(template),
          hasLength(2),
          reason: '$app needs an app key vector and a synced item vector');
    }
  });
}
