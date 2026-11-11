import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/zt_preferences.dart';
import 'zt_crash_report.dart';

/// What the person chose in Settings → Crash reports.
enum ZtCrashReportMode {
  /// Nothing is recorded. The default.
  off,

  /// Reports are kept on the phone; nothing leaves it until the person
  /// reads one and taps Send (or copies it).
  ask,

  /// Reports are sent as they happen. Only offered when the app has a
  /// [ZtCrashReportSink].
  automatic;

  static ZtCrashReportMode parse(String? s) => values.firstWhere(
        (m) => m.name == s,
        orElse: () => ZtCrashReportMode.off,
      );
}

/// Where reports go. One `send` per report; throw on failure so the report
/// is kept and tried again later.
abstract interface class ZtCrashReportSink {
  Future<void> send(ZtCrashReport report);
}

/// Posts [ZtCrashReport.toPayload] as JSON to [endpoint]. Sends no account
/// token or cookie, so the server can't tell who sent it. [headers] is for
/// a public key the endpoint needs (for example a Supabase anon key),
/// never a user's.
class ZtHttpCrashReportSink implements ZtCrashReportSink {
  ZtHttpCrashReportSink(this.endpoint,
      {this.headers = const {}, http.Client? client})
      : _client = client ?? http.Client();

  final Uri endpoint;
  final Map<String, String> headers;
  final http.Client _client;

  @override
  Future<void> send(ZtCrashReport report) async {
    final response = await _client
        .post(
          endpoint,
          headers: {...headers, 'content-type': 'application/json'},
          body: jsonEncode(report.toPayload()),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Crash report not accepted (${response.statusCode})',
          uri: endpoint);
    }
  }
}

/// Saved reports. [save] is synchronous on purpose: it may run while the
/// app is going down.
abstract interface class ZtCrashReportStore {
  Future<List<ZtCrashReport>> load();
  void save(List<ZtCrashReport> reports);
}

class InMemoryCrashReportStore implements ZtCrashReportStore {
  List<ZtCrashReport> saved = [];

  @override
  Future<List<ZtCrashReport>> load() async => [...saved];

  @override
  void save(List<ZtCrashReport> reports) => saved = [...reports];
}

/// `crash_reports.json` in the app's private support folder. Holds no
/// user content (see [ZtCrashScrubber]), so it isn't encrypted.
class FileCrashReportStore implements ZtCrashReportStore {
  FileCrashReportStore([this._file]);

  File? _file;

  Future<File> _resolve() async => _file ??= File(
      '${(await getApplicationSupportDirectory()).path}/zt_crash_reports.json');

  @override
  Future<List<ZtCrashReport>> load() async {
    try {
      final file = await _resolve();
      if (!file.existsSync()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return [
        for (final j in list)
          ZtCrashReport.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return []; // Unreadable: start over rather than fail.
    }
  }

  @override
  void save(List<ZtCrashReport> reports) {
    final file = _file;
    if (file == null) return; // Not loaded yet.
    try {
      if (reports.isEmpty) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(jsonEncode([for (final r in reports) r.toJson()]),
          flush: true);
    } on Object {
      // Never let crash reporting cause a crash.
    }
  }
}

/// Opt-in crash reports for every Zero-Trust app (Z15). Off by default;
/// records nothing until the person turns it on in settings. Reports are
/// scrubbed by [ZtCrashScrubber] and, with [ZtCrashReportMode.ask], only
/// leave the phone when the person reads one and taps Send.
///
/// In `main()`:
/// ```dart
/// final crashes = ZtCrashReporter(appId: 'notes', appVersion: '0.4.1+12');
/// crashes.install();
/// await crashes.load();
/// runApp(ProviderScope(overrides: [
///   ztCrashReporterProvider.overrideWithValue(crashes), ...
/// ```
class ZtCrashReporter extends ChangeNotifier {
  ZtCrashReporter({
    required this.appId,
    this.appVersion = '',
    this.sink,
    PreferencesStore? preferences,
    ZtCrashReportStore? store,
    String? platform,
    DateTime Function()? now,
    Random? random,
  })  : _preferences = preferences ?? SecurePreferencesStore(),
        _store = store ?? FileCrashReportStore(),
        _platform = platform ?? defaultTargetPlatform.name.toLowerCase(),
        _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  static const prefKey = 'crash_reports';

  /// Saved reports kept at most; the oldest go first.
  static const maxSaved = 10;

  /// Errors seen before [load] knows the choice: kept in memory only.
  static const _maxEarly = 3;

  final String appId;
  final String appVersion;

  /// Null until Edo picks where reports go: then only "Off" and "Ask me"
  /// (keep, read, copy) are offered.
  final ZtCrashReportSink? sink;

  final PreferencesStore _preferences;
  final ZtCrashReportStore _store;
  final String _platform;
  final DateTime Function() _now;
  final Random _random;

  ZtCrashReportMode _mode = ZtCrashReportMode.off;
  List<ZtCrashReport> _reports = [];
  final List<ZtCrashReport> _early = [];
  bool _loaded = false;
  bool _recording = false;
  Future<void>? _sending;

  /// Changes whenever the person changes the choice or deletes reports, so
  /// a batch upload already under way stops before its next report.
  int _consent = 0;

  ZtCrashReportMode get mode => _mode;

  /// Reports on this phone not yet sent, newest first.
  List<ZtCrashReport> get reports => List.unmodifiable(_reports.reversed);

  bool get canSend => sink != null;

  /// Reads the person's choice and saved reports. Sends what's waiting
  /// when they chose automatic.
  Future<void> load() async {
    String? stored;
    try {
      stored = await _preferences.read(prefKey);
    } on Object {
      stored = null;
    }
    var mode = ZtCrashReportMode.parse(stored);
    if (mode == ZtCrashReportMode.automatic && sink == null) {
      mode = ZtCrashReportMode.ask;
    }
    _mode = mode;
    final saved = await _store.load();
    _loaded = true;
    if (_mode == ZtCrashReportMode.off) {
      _reports = [];
      if (saved.isNotEmpty) _store.save(const []);
    } else {
      _reports = saved;
      for (final r in _early) {
        _add(r);
      }
      _store.save(_reports);
    }
    _early.clear();
    notifyListeners();
    if (_mode == ZtCrashReportMode.automatic) unawaited(sendAll());
  }

  /// Hooks Flutter's two error handlers, keeping whatever was there before
  /// (so errors still print in debug builds). Call once, early in main().
  void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack,
          uncaught: false, library: details.library);
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousPlatform = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      record(error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  /// Records one error, if the person turned reports on. Also for apps
  /// that catch an error themselves and want it reported.
  void record(Object error, StackTrace? stack,
      {bool uncaught = true, String? library}) {
    if (_recording) return; // An error while recording: drop it.
    if (_loaded && _mode == ZtCrashReportMode.off) return;
    _recording = true;
    try {
      final report = ZtCrashScrubber.build(
        error: error,
        stack: stack,
        appId: appId,
        appVersion: appVersion,
        platform: _platform,
        now: _now(),
        id: _newId(),
        uncaught: uncaught,
        library: library,
      );
      if (!_loaded) {
        if (_early.length < _maxEarly) _early.add(report);
        return;
      }
      _add(report);
      _store.save(_reports);
      notifyListeners();
      if (_mode == ZtCrashReportMode.automatic) unawaited(sendAll());
    } on Object {
      // Never let crash reporting cause a crash.
    } finally {
      _recording = false;
    }
  }

  /// Same bug again: count it instead of keeping a copy.
  void _add(ZtCrashReport report) {
    final i = _reports.indexWhere((r) =>
        r.fingerprint == report.fingerprint &&
        r.appVersion == report.appVersion);
    if (i >= 0) {
      final same = _reports.removeAt(i);
      _reports.add(same.copyWith(count: same.count + report.count));
    } else {
      _reports.add(report);
    }
    while (_reports.length > maxSaved) {
      _reports.removeAt(0);
    }
  }

  Future<void> setMode(ZtCrashReportMode mode) async {
    if (mode == ZtCrashReportMode.automatic && sink == null) {
      throw StateError('No crash report destination configured');
    }
    _mode = mode;
    _consent++;
    if (mode == ZtCrashReportMode.off) {
      _reports = [];
      _store.save(const []);
    }
    notifyListeners();
    await _preferences.write(prefKey, mode.name);
    if (mode == ZtCrashReportMode.automatic) await sendAll();
  }

  /// Sends one report and removes it. Throws when it couldn't be sent.
  Future<void> send(String id) async {
    final target = sink;
    if (target == null) throw StateError('No crash report destination');
    final report = _reports.firstWhere((r) => r.id == id);
    await target.send(report);
    _acknowledge(report);
  }

  /// Takes what [sent] covered off the queue. The same bug may have
  /// happened again during the upload: those extra times stay pending.
  void _acknowledge(ZtCrashReport sent) {
    final i = _reports.indexWhere((r) => r.id == sent.id);
    if (i < 0) return;
    final now = _reports[i];
    if (now.count > sent.count) {
      _reports[i] = now.copyWith(count: now.count - sent.count);
    } else {
      _reports.removeAt(i);
    }
    _store.save(_reports);
    notifyListeners();
  }

  /// Sends every saved report; keeps the ones that fail for next time.
  Future<void> sendAll() => _sending ??= _sendAll().whenComplete(() {
        _sending = null;
      });

  Future<void> _sendAll() async {
    final target = sink;
    if (target == null) return;
    final consent = _consent;
    for (final queued in [..._reports]) {
      // Stop if the person turned reports off, switched to asking, or
      // deleted reports since this batch started.
      if (_consent != consent || _mode == ZtCrashReportMode.off) return;
      final i = _reports.indexWhere((r) => r.id == queued.id);
      if (i < 0) continue;
      final report = _reports[i];
      try {
        await target.send(report);
      } on Object {
        return; // Offline or refused: try again on the next start.
      }
      _acknowledge(report);
    }
  }

  void delete(String id) {
    _consent++;
    _reports.removeWhere((r) => r.id == id);
    _store.save(_reports);
    notifyListeners();
  }

  void deleteAll() {
    _consent++;
    _reports = [];
    _store.save(const []);
    notifyListeners();
  }

  String _newId() {
    final b = StringBuffer();
    for (var i = 0; i < 8; i++) {
      b.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}

/// The app's [ZtCrashReporter], or null when the app hasn't set one up
/// (then the settings row is hidden). Apps override it in `ProviderScope`.
final ztCrashReporterProvider = Provider<ZtCrashReporter?>((ref) => null);
