import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'apk/dex_types.dart';
import 'apk/zip_reader.dart';
import 'static_checks.dart';

/// A kit that app makers build into their apps and that reports to its own
/// company: advertising, statistics, location, crash reports. It is known
/// by the Java packages its code lives in.
class Tracker {
  const Tracker({required this.id, required this.name, required this.code});

  factory Tracker.fromJson(Map<String, Object?> json) => Tracker(
        id: (json['id']! as num).toInt(),
        name: json['name']! as String,
        code: (json['code']! as List).cast<String>(),
      );

  /// Exodus Privacy's number for it.
  final int id;
  final String name;

  /// Names its code goes by: mostly the start of a Java package
  /// (`com.example.tracker.`), now and then the end of a class name
  /// (`.TrackerManager`).
  final List<String> code;
}

/// The tracker list this package carries: Exodus Privacy's database, under
/// the Open Database License, cut down to what a scan of code uses. The
/// same file ZT Privacy ships; see data/NOTICE.md.
List<Tracker> parseTrackerList(String text) => [
      for (final tracker
          in (jsonDecode(text) as Map<String, Object?>)['trackers']! as List)
        Tracker.fromJson((tracker as Map).cast<String, Object?>()),
    ];

/// Reads data/exodus_trackers.json from wherever this package is installed.
Future<List<Tracker>> loadTrackerList() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:zt_release_checks/zt_release_checks.dart'));
  final root = p.dirname(p.dirname(lib!.toFilePath()));
  return parseTrackerList(
      File(p.join(root, 'data', 'exodus_trackers.json')).readAsStringSync());
}

/// One name from [Tracker.code], as it is written among the class names in
/// an app's code (`Lcom/example/tracker/Client;`).
class _Signature {
  _Signature(String name)
      : anywhere = name.startsWith('.'),
        bytes = Uint8List.fromList((name.startsWith('.')
                ? name.replaceAll('.', '/')
                : 'L${name.replaceAll('.', '/')}')
            .codeUnits);

  /// A name that starts with a dot is the end of a class name and may sit
  /// under any package. Every other name must be the start of the class
  /// name. The same rule as ZT Privacy's scan.
  final bool anywhere;
  final Uint8List bytes;

  bool isIn(DexTypes dex) =>
      anywhere ? dex.hasPart(bytes) : dex.hasPrefix(bytes);

  bool fits(String className) {
    final text = String.fromCharCodes(bytes);
    return anywhere ? className.contains(text) : className.startsWith(text);
  }
}

/// A tracker whose code is in an app, with a few of the class names that
/// gave it away.
class TrackerFound {
  TrackerFound(this.tracker);

  final Tracker tracker;
  final List<String> classNames = [];
}

/// What a scan of one APK or app bundle found.
class ApkTrackerScan {
  /// By tracker id.
  final Map<int, TrackerFound> found = {};

  /// Code files read, and the class names in them.
  int codeFiles = 0;
  int classNames = 0;

  /// Files that could not be read, each with the reason.
  final List<String> errors = [];
}

/// `classes.dex`, `classes2.dex` at the top of an APK, or under
/// `base/dex/` and the like in an app bundle.
final _dexName = RegExp(r'(^|/)classes\d*\.dex$');

/// No real code file is near this size; anything larger is not unpacked.
const _largestDex = 96 * 1024 * 1024;

/// The most class names shown for one tracker.
const _examples = 3;

/// Looks for the code of [trackers] among the class names in [file], an
/// APK or an app bundle.
///
/// It reads names only: it says a kit's code is in the app, not that the
/// code ever runs, and it cannot see code whose names were scrambled.
ApkTrackerScan scanForTrackers(File file, List<Tracker> trackers) {
  final result = ApkTrackerScan();
  final wanted = [
    for (final tracker in trackers)
      (tracker, [for (final name in tracker.code) _Signature(name)]),
  ];
  RandomAccessFile? open;
  try {
    open = file.openSync();
    final zip = ZipReader(open);
    for (final entry in zip.entries()) {
      if (!_dexName.hasMatch(entry.name)) continue;
      if (entry.uncompressedSize > _largestDex) {
        result.errors.add('${entry.name}: too large to read');
        continue;
      }
      try {
        final dex = DexTypes.parse(zip.read(entry));
        result.codeFiles++;
        result.classNames += dex.typeCount;
        for (final (tracker, signatures) in wanted) {
          final here = [
            for (final signature in signatures)
              if (signature.isIn(dex)) signature,
          ];
          if (here.isEmpty) continue;
          final found =
              result.found.putIfAbsent(tracker.id, () => TrackerFound(tracker));
          // Only now the slow walk over every name, to show which ones.
          for (var i = 0;
              i < dex.typeCount && found.classNames.length < _examples;
              i++) {
            final name = dex.nameAt(i);
            if (here.any((s) => s.fits(name)) &&
                !found.classNames.contains(name)) {
              found.classNames.add(name);
            }
          }
        }
      } on FormatException catch (e) {
        result.errors.add('${entry.name}: ${e.message}');
      }
    }
  } on FormatException catch (e) {
    result.errors.add(e.message);
  } on FileSystemException catch (e) {
    result.errors.add(e.osError?.message ?? e.message);
  } finally {
    open?.closeSync();
  }
  return result;
}

/// `Lcom/example/tracker/Client;` as people write it.
String _plain(String className) => className.startsWith('L')
    ? className.substring(1).replaceAll('/', '.').replaceAll(';', '')
    : className;

/// The check: none of [files] (the APKs or app bundles of one build) has
/// code from a tracker on the list. A file whose code could not be read
/// fails as well: a scan that read nothing has shown nothing.
///
/// [read] is told, for each file that was read, how much code was in it.
CheckResult checkNoTrackers(
  List<File> files,
  List<Tracker> trackers, {
  void Function(String file, ApkTrackerScan scan)? read,
}) {
  final problems = <String>[];
  if (files.isEmpty) problems.add('No APK or app bundle was given.');
  for (final file in files) {
    final name = p.basename(file.path);
    if (!file.existsSync()) {
      problems.add('$name: no such file.');
      continue;
    }
    final scan = scanForTrackers(file, trackers);
    read?.call(name, scan);
    for (final error in scan.errors) {
      problems.add('$name: could not be read ($error).');
    }
    if (scan.codeFiles == 0 && scan.errors.isEmpty) {
      problems.add('$name: no code (classes.dex) was found in it.');
    }
    final found = scan.found.values.toList()
      ..sort((a, b) => a.tracker.name.compareTo(b.tracker.name));
    for (final one in found) {
      problems.add('$name contains code from ${one.tracker.name} '
          '(Exodus Privacy no. ${one.tracker.id}), for example '
          '${one.classNames.map(_plain).join(', ')}. Find the dependency '
          'that brings it in and remove or replace it.');
    }
  }
  return CheckResult('no tracker code', problems);
}

/// Scans the files at [paths], prints a report, and returns whether none
/// has tracker code.
Future<bool> runTrackerCheck(List<String> paths) async {
  final trackers = await loadTrackerList();
  final lines = <String>[];
  final result = checkNoTrackers(
    [for (final path in paths) File(path)],
    trackers,
    read: (file, scan) => lines.add('$file: ${scan.codeFiles} code '
        '${scan.codeFiles == 1 ? 'file' : 'files'}, ${scan.classNames} '
        'class names read'),
  );
  stdout.writeln('${result.ok ? 'PASS' : 'FAIL'}  ${result.name} '
      '(${trackers.length} trackers looked for)');
  for (final line in lines) {
    stdout.writeln('      $line');
  }
  for (final problem in result.problems) {
    stdout.writeln('      - $problem');
  }
  return result.ok;
}
