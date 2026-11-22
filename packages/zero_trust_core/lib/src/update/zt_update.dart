import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/zt_app_config.dart';
import '../config/zt_install_channel.dart';
import '../config/zt_preferences.dart';

/// The newest signed release of an app on GitHub (S-1).
@immutable
class ZtRelease {
  const ZtRelease({
    required this.version,
    required this.tag,
    required this.page,
    this.apk,
    this.notes = '',
  });

  /// "0.7.0", from a tag like `v0.7.0-build1012`.
  final String version;
  final String tag;

  /// The release on GitHub.
  final Uri page;

  /// The signed APK, when the release has one.
  final Uri? apk;

  /// Release notes as written on GitHub (Markdown).
  final String notes;

  /// Where "Download" goes: the APK itself, or the release page.
  Uri get downloadUrl => apk ?? page;

  /// Reads one `releases/latest` answer. Null when it has no usable
  /// version number.
  static ZtRelease? fromGitHub(Map<String, Object?> json) {
    final tag = json['tag_name'];
    final page = json['html_url'];
    if (tag is! String || page is! String) return null;
    final version = ztVersionOf(tag);
    if (version == null) return null;
    final apks = <String, Uri>{};
    for (final a in (json['assets'] as List<Object?>? ?? const [])) {
      if (a is! Map) continue;
      final name = a['name'];
      final url = a['browser_download_url'];
      if (name is String &&
          url is String &&
          name.toLowerCase().endsWith('.apk')) {
        apks[name.toLowerCase()] = Uri.parse(url);
      }
    }
    return ZtRelease(
      version: version.join('.'),
      tag: tag,
      page: Uri.parse(page),
      apk: _pickApk(apks),
      notes: (json['body'] as String? ?? '').trim(),
    );
  }

  /// One APK: the only one, else a universal build, else arm64 (every
  /// phone the suite supports), else the first.
  static Uri? _pickApk(Map<String, Uri> apks) {
    if (apks.length <= 1) return apks.values.firstOrNull;
    for (final hint in ['universal', 'arm64']) {
      for (final e in apks.entries) {
        if (e.key.contains(hint)) return e.value;
      }
    }
    return apks.values.first;
  }
}

/// The numbers of a version or tag: `v0.7.0-build1012` and `0.7.0+12`
/// both give `[0, 7, 0]`. Null when there are none.
List<int>? ztVersionOf(String text) {
  final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(text);
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i) ?? '0')];
}

/// Whether [latest] is a newer version than [installed]. Build numbers
/// are ignored: a version rises with every release (Dev -> main).
bool ztIsNewerVersion(String latest, String installed) {
  final a = ztVersionOf(latest);
  final b = ztVersionOf(installed);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Asks GitHub for an app's latest release. Sends nothing about the person
/// or the account: one anonymous request for public data.
class ZtReleaseSource {
  ZtReleaseSource({required this.repo, http.Client? client})
      : _client = client ?? http.Client();

  /// `owner/name`, for example `EdoSag/Zero-Trust-Notes`.
  final String repo;
  final http.Client _client;

  Uri get _latestUrl =>
      Uri.https('api.github.com', '/repos/$repo/releases/latest');

  /// Null when the app has no release yet. Throws when GitHub can't be
  /// reached or answers with an error.
  Future<ZtRelease?> latest() async {
    final res = await _client.get(_latestUrl, headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'zero-trust-app',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw http.ClientException(
          'GitHub answered ${res.statusCode}', _latestUrl);
    }
    final json = jsonDecode(res.body);
    return json is Map<String, Object?> ? ZtRelease.fromGitHub(json) : null;
  }
}

/// What a check found.
@immutable
class ZtUpdateStatus {
  const ZtUpdateStatus({required this.installed, this.latest});

  final String installed;

  /// Null when the app has no release on GitHub yet.
  final ZtRelease? latest;

  /// The newer release, or null when this is the newest.
  ZtRelease? get update =>
      latest != null && ztIsNewerVersion(latest!.version, installed)
          ? latest
          : null;
}

/// In-app update check for builds installed from GitHub (S-1).
///
/// Only direct Android builds ([ZtInstallChannel.direct]) check: Google
/// Play and the App Store update their own builds and forbid apps that
/// update themselves. On by default; the person can turn it off in
/// Settings. Checks at most once a day on launch, and when Settings opens.
class ZtUpdates {
  ZtUpdates({
    required this.source,
    required this.installedVersion,
    required this.preferences,
  });

  final ZtReleaseSource source;
  final Future<String?> Function() installedVersion;
  final PreferencesStore preferences;

  static const _enabledKey = 'updates_check';
  static const _lastCheckKey = 'updates_last_check';
  static const _announcedKey = 'updates_announced';

  /// How often the launch check runs at most.
  static const launchInterval = Duration(hours: 24);

  /// The Obtainium link for this app: adds it to Obtainium (a free app
  /// that installs updates straight from GitHub), or explains Obtainium
  /// when it isn't installed.
  Uri get obtainiumUrl => Uri.https('apps.obtainium.imranr.dev', '/redirect',
      {'r': 'obtainium://add/https://github.com/${source.repo}'});

  Future<bool> enabled() async => await _read(_enabledKey) != 'false';

  Future<void> setEnabled(bool on) => preferences.write(_enabledKey, '$on');

  /// Checks now, whatever the setting (the person asked). Throws when
  /// GitHub can't be reached or the installed version is unknown.
  Future<ZtUpdateStatus> check() async {
    final installed = await installedVersion();
    if (installed == null) throw StateError('Installed version unknown');
    final latest = await source.latest();
    await preferences.write(
        _lastCheckKey, clock.now().toUtc().toIso8601String());
    return ZtUpdateStatus(installed: installed, latest: latest);
  }

  /// The launch check: a newer release the person hasn't been told about
  /// yet, at most once a day and only while the setting is on. Never
  /// throws; null on any failure.
  Future<ZtUpdateStatus?> launchNotice() async {
    try {
      if (!await enabled()) return null;
      final last = DateTime.tryParse(await _read(_lastCheckKey) ?? '');
      if (last != null && clock.now().difference(last) < launchInterval) {
        return null;
      }
      final status = await check();
      final update = status.update;
      if (update == null || await _read(_announcedKey) == update.version) {
        return null;
      }
      await preferences.write(_announcedKey, update.version);
      return status;
    } on Object {
      return null;
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await preferences.read(key);
    } on Object {
      return null;
    }
  }
}

/// Whether this build may check GitHub for updates.
bool ztUpdatesSupported(ZtAppConfig config) =>
    config.channel == ZtInstallChannel.direct &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android;

/// The installed version name ("0.6.0"). Tests override it.
final ztInstalledVersionProvider = FutureProvider<String?>((ref) async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } on Object {
    return null;
  }
});

/// Where release data comes from. Tests override it.
final ztReleaseSourceProvider = Provider<ZtReleaseSource>(
    (ref) => ZtReleaseSource(repo: ref.watch(ztAppConfigProvider).releaseRepo));

/// The update check, or null in builds that must not update themselves.
final ztUpdatesProvider = Provider<ZtUpdates?>((ref) {
  if (!ztUpdatesSupported(ref.watch(ztAppConfigProvider))) return null;
  return ZtUpdates(
    source: ref.watch(ztReleaseSourceProvider),
    installedVersion: () => ref.read(ztInstalledVersionProvider.future),
    preferences: ref.watch(ztPreferencesStoreProvider),
  );
});

/// Opens a link outside the app (the browser downloads the APK and hands
/// it to Android's installer). Tests override it.
final ztOpenExternalUrlProvider = Provider<Future<bool> Function(Uri)>(
    (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication));
