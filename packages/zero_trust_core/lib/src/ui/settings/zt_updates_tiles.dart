import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../l10n/zt_l10n.dart';
import '../../update/zt_update.dart';

/// Settings rows for builds installed from GitHub (S-1): the update status
/// (tap to update or check again), the daily check switch, and a link to
/// add the app to Obtainium. Shows nothing in store builds.
class ZtUpdatesTiles extends ConsumerStatefulWidget {
  const ZtUpdatesTiles({super.key});

  @override
  ConsumerState<ZtUpdatesTiles> createState() => _ZtUpdatesTilesState();
}

enum _Phase { checking, done, failed }

class _ZtUpdatesTilesState extends ConsumerState<ZtUpdatesTiles> {
  _Phase _phase = _Phase.checking;
  ZtUpdateStatus? _status;
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    final updates = ref.read(ztUpdatesProvider);
    if (updates == null) return;
    unawaited(updates.enabled().then((on) {
      if (mounted) setState(() => _enabled = on);
    }));
    unawaited(_check());
  }

  Future<void> _check() async {
    final updates = ref.read(ztUpdatesProvider);
    if (updates == null) return;
    setState(() => _phase = _Phase.checking);
    try {
      final status = await updates.check();
      if (mounted) {
        setState(() {
          _status = status;
          _phase = _Phase.done;
        });
      }
    } on Object {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(ztUpdatesProvider);
    if (updates == null) return const SizedBox.shrink();
    final l = ZtL10n.of(context);
    final update = _status?.update;
    final String subtitle = switch (_phase) {
      _Phase.checking => l.checkingForUpdates,
      _Phase.failed => l.couldNotCheckForUpdates,
      _Phase.done when update != null =>
        l.updateAvailableVersion(update.version),
      _Phase.done when _status!.latest == null => l.noReleaseYet,
      _Phase.done => l.youHaveTheLatestVersion(_status!.installed),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('zt-app-updates'),
          leading: Icon(update != null
              ? Icons.system_update
              : Icons.system_update_outlined),
          title: Text(l.appUpdates),
          subtitle: Text(subtitle),
          onTap: switch (_phase) {
            _Phase.checking => null,
            _ when update != null => () =>
                ztShowUpdateDialog(context, ref, _status!),
            _ => _check,
          },
        ),
        SwitchListTile(
          key: const ValueKey('zt-check-updates'),
          secondary: const Icon(Icons.update),
          title: Text(l.checkForUpdates),
          subtitle: Text(l.checkForUpdatesSubtitle),
          value: _enabled ?? true,
          onChanged: _enabled == null
              ? null
              : (on) {
                  setState(() => _enabled = on);
                  unawaited(updates.setEnabled(on));
                },
        ),
        ListTile(
          key: const ValueKey('zt-obtainium'),
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(l.getUpdatesWithObtainium),
          subtitle: Text(l.obtainiumSubtitle),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: () => _open(context, ref, updates.obtainiumUrl),
        ),
      ],
    );
  }
}

/// The "Update available" dialog: what's new, and Download, which hands
/// the signed APK to the browser and from there to Android's installer.
Future<void> ztShowUpdateDialog(
    BuildContext context, WidgetRef ref, ZtUpdateStatus status) {
  final release = status.update ?? status.latest!;
  final app = ref.read(ztAppConfigProvider).displayName;
  final open = ref.read(ztOpenExternalUrlProvider);
  return _showUpdateDialog(context, app, status.installed, release, open);
}

Future<void> _showUpdateDialog(BuildContext context, String app,
    String installed, ZtRelease release, Future<bool> Function(Uri) open) {
  final notes = release.notes.length > 1500
      ? '${release.notes.substring(0, 1500)}…'
      : release.notes;
  return showDialog<void>(
    context: context,
    builder: (context) {
      final l = ZtL10n.of(context);
      final theme = Theme.of(context);
      return AlertDialog(
        icon: const Icon(Icons.system_update),
        title: Text(l.updateAvailableTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.updateAvailableBody(app, release.version, installed)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(l.whatsNew, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(notes, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              Text(l.updateHowItInstalls,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.notNow),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_openWith(context, open, release.downloadUrl));
            },
            child: Text(l.downloadUpdate),
          ),
        ],
      );
    },
  );
}

Future<void> _open(BuildContext context, WidgetRef ref, Uri url) =>
    _openWith(context, ref.read(ztOpenExternalUrlProvider), url);

Future<void> _openWith(
    BuildContext context, Future<bool> Function(Uri) open, Uri url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = ZtL10n.current.couldNotOpenLink;
  bool ok;
  try {
    ok = await open(url);
  } on Object {
    ok = false;
  }
  if (!ok) {
    messenger?.showSnackBar(
        SnackBar(content: Text(failed), duration: const Duration(seconds: 4)));
  }
}

/// Call right after sign-in or unlock (the core's screens do). Once a day
/// at most, and once per new version, tells the person an update is ready.
/// Runs in the background and never throws; does nothing in store builds.
Future<void> ztCheckForUpdateAfterUnlock(
    NavigatorState navigator, ProviderContainer container) async {
  final updates = container.read(ztUpdatesProvider);
  if (updates == null) return;
  final app = container.read(ztAppConfigProvider).displayName;
  final open = container.read(ztOpenExternalUrlProvider);
  final status = await updates.launchNotice();
  final release = status?.update;
  if (status == null || release == null || !navigator.mounted) return;
  await _showUpdateDialog(
      navigator.context, app, status.installed, release, open);
}
