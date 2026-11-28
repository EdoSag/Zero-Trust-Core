import 'dart:io';

import 'package:test/test.dart';
import 'package:zt_release_checks/zt_release_checks.dart';

import 'support/fake_files.dart';

const adNetwork = Tracker(id: 11, name: 'Ad Network', code: ['com.adnet.']);
const appStats = Tracker(
  id: 12,
  name: 'App Stats',
  code: ['io.appstats.sdk.', '.StatsReporter'],
);
const trackers = [adNetwork, appStats];

const ownCode = [
  'Ldev/sagron/zerotrustnotes/MainActivity;',
  'Lio/flutter/embedding/android/FlutterActivity;',
  'Landroidx/core/app/ActivityCompat;',
];

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('zt_trackers'));
  tearDown(() => folder.deleteSync(recursive: true));

  File apk(String name, Map<String, List<String>> dexFiles) => File(writeFile(
        folder,
        name,
        fakeZip([
          const FakeEntry('AndroidManifest.xml', [1, 2, 3]),
          for (final entry in dexFiles.entries)
            FakeEntry(entry.key, fakeDex(entry.value)),
        ]),
      ));

  test('an app with only its own code passes', () {
    final file = apk('app-release.apk', {
      'classes.dex': ownCode,
      'classes2.dex': ['Lcom/example/Helper;'],
    });
    final seen = <String, ApkTrackerScan>{};
    final result = checkNoTrackers([file], trackers,
        read: (name, scan) => seen[name] = scan);
    expect(result.problems, isEmpty);
    expect(result.ok, isTrue);
    expect(seen.keys, ['app-release.apk']);
    expect(seen.values.single.codeFiles, 2);
    expect(seen.values.single.classNames, ownCode.length + 1);
  });

  test('tracker code fails, with its name, number and where it sits', () {
    final file = apk('app-release.apk', {
      'classes.dex': ownCode,
      'classes2.dex': [
        'Lcom/adnet/Banner;',
        'Lcom/adnet/internal/Loader;',
        'Lcom/adnet/internal/a;',
        'Lcom/adnet/internal/b;',
      ],
    });
    final result = checkNoTrackers([file], trackers);
    expect(result.ok, isFalse);
    expect(result.problems, hasLength(1));
    final problem = result.problems.single;
    expect(problem, contains('app-release.apk contains code from Ad Network'));
    expect(problem, contains('Exodus Privacy no. 11'));
    // Three class names at most, written the way people write them.
    expect(
        problem,
        contains('com.adnet.Banner, com.adnet.internal.Loader, '
            'com.adnet.internal.a.'));
    expect(problem, isNot(contains('com.adnet.internal.b')));
  });

  test('a name that only ends like a tracker\'s is found anywhere', () {
    final file = apk('app.apk', {
      'classes.dex': [...ownCode, 'Lcom/renamed/StatsReporter;'],
    });
    final result = checkNoTrackers([file], trackers);
    expect(result.problems.single, contains('App Stats'));
    expect(result.problems.single, contains('com.renamed.StatsReporter'));
  });

  test('a package that only looks alike is not a tracker', () {
    final file = apk('app.apk', {
      'classes.dex': [
        ...ownCode,
        // Not under com.adnet., and not at the start of the name.
        'Lcom/adnetwork/Banner;',
        'Lorg/com/adnet/Banner;',
        'Lio/appstats/Other;',
      ],
    });
    expect(checkNoTrackers([file], trackers).ok, isTrue);
  });

  test('each tracker is told once, in order of name, over all code files', () {
    final file = apk('app.apk', {
      'classes.dex': ['Lio/appstats/sdk/Client;', 'Lcom/adnet/Banner;'],
      'classes2.dex': ['Lcom/adnet/Other;'],
    });
    final result = checkNoTrackers([file], trackers);
    expect(result.problems, hasLength(2));
    expect(result.problems[0], contains('Ad Network'));
    expect(result.problems[1], contains('App Stats'));
  });

  test('an app bundle keeps its code under base/dex and is read too', () {
    final file = apk('app-release.aab', {
      'base/dex/classes.dex': ownCode,
      'feature/dex/classes2.dex': ['Lcom/adnet/Banner;'],
      // Not code: a file that only has the name inside it.
      'base/assets/notclasses.dex.txt': ['Lio/appstats/sdk/Client;'],
    });
    final seen = <ApkTrackerScan>[];
    final result =
        checkNoTrackers([file], trackers, read: (_, scan) => seen.add(scan));
    expect(seen.single.codeFiles, 2);
    expect(result.problems.single, contains('Ad Network'));
  });

  test('every file of the build is read', () {
    final clean = apk('app-arm64-v8a-release.apk', {'classes.dex': ownCode});
    final dirty = apk('app-x86_64-release.apk', {
      'classes.dex': ['Lcom/adnet/Banner;'],
    });
    final result = checkNoTrackers([clean, dirty], trackers);
    expect(result.problems.single,
        startsWith('app-x86_64-release.apk contains code from Ad Network'));
  });

  group('a scan that read nothing does not pass', () {
    test('no file given', () {
      expect(checkNoTrackers([], trackers).problems,
          ['No APK or app bundle was given.']);
    });

    test('a file that is not there', () {
      final result =
          checkNoTrackers([File('${folder.path}/missing.apk')], trackers);
      expect(result.problems, ['missing.apk: no such file.']);
    });

    test('a file that is not a zip', () {
      final file = File(writeFile(folder, 'broken.apk', List.filled(64, 7)));
      final result = checkNoTrackers([file], trackers);
      expect(result.ok, isFalse);
      expect(
          result.problems.single, startsWith('broken.apk: could not be read'));
    });

    test('a zip with no code in it', () {
      final file = apk('empty.apk', {});
      expect(checkNoTrackers([file], trackers).problems,
          ['empty.apk: no code (classes.dex) was found in it.']);
    });

    test('a code file that is not code', () {
      final file = File(writeFile(
        folder,
        'odd.apk',
        fakeZip([
          FakeEntry('classes.dex', fakeDex(ownCode)),
          const FakeEntry('classes2.dex', [1, 2, 3, 4]),
        ]),
      ));
      final result = checkNoTrackers([file], trackers);
      expect(result.problems,
          ['odd.apk: could not be read (classes2.dex: not a DEX file).']);
    });
  });

  group('the list this package carries', () {
    late List<Tracker> carried;
    setUpAll(() async => carried = await loadTrackerList());

    test('is found from wherever the package is, and is the full list', () {
      expect(carried.length, greaterThan(400));
      expect(carried.map((t) => t.id).toSet().length, carried.length);
      for (final tracker in carried) {
        expect(tracker.code, isNotEmpty, reason: tracker.name);
        for (final name in tracker.code) {
          // A name short enough to match half of Android would fail every
          // build.
          expect(name.length, greaterThan(4), reason: tracker.name);
        }
      }
    });

    test('finds the well known ones in an app that has them', () {
      final file = apk('app.apk', {
        'classes.dex': [
          ...ownCode,
          'Lcom/google/firebase/analytics/FirebaseAnalytics;',
          'Lcom/google/firebase/crashlytics/CrashlyticsRegistrar;',
          'Lcom/facebook/ads/AdView;',
        ],
      });
      final result = checkNoTrackers([file], carried);
      expect(result.problems, hasLength(3));
      expect(result.problems.join('\n'), contains('Google Firebase Analytics'));
      expect(result.problems.join('\n'), contains('Google CrashLytics'));
    });

    test('lets the code of a plain Flutter app through', () {
      final file = apk('app.apk', {
        'classes.dex': [
          ...ownCode,
          'Lio/flutter/plugins/GeneratedPluginRegistrant;',
          'Landroidx/work/WorkManager;',
          'Lkotlin/jvm/internal/Intrinsics;',
          'Lcom/google/android/material/button/MaterialButton;',
          'Lcom/it_nomads/fluttersecurestorage/FlutterSecureStoragePlugin;',
        ],
      });
      expect(checkNoTrackers([file], carried).problems, isEmpty);
    });
  });
}
