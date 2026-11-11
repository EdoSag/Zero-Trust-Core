import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crash/zt_crash_report.dart';
import '../../crash/zt_crash_reporter.dart';
import '../../l10n/zt_l10n.dart';

String _modeLabel(ZtLocalizations l, ZtCrashReportMode mode, bool canSend) =>
    switch (mode) {
      ZtCrashReportMode.off => l.crashReportsOff,
      ZtCrashReportMode.ask => canSend ? l.crashReportsAsk : l.crashReportsKeep,
      ZtCrashReportMode.automatic => l.crashReportsAutomatic,
    };

/// Settings row for crash reports (Z15). Hidden unless the app set up
/// [ztCrashReporterProvider].
class ZtCrashReportsTile extends ConsumerWidget {
  const ZtCrashReportsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reporter = ref.watch(ztCrashReporterProvider);
    if (reporter == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: reporter,
      builder: (context, _) {
        final l = ZtL10n.of(context);
        return ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l.crashReports),
          subtitle: Text(_modeLabel(l, reporter.mode, reporter.canSend)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ZtCrashReportsScreen(reporter: reporter))),
        );
      },
    );
  }
}

/// What crash reports contain, the off / ask / automatic choice, and the
/// reports saved on this phone with Send, Copy and Delete.
class ZtCrashReportsScreen extends StatelessWidget {
  const ZtCrashReportsScreen({super.key, required this.reporter});

  final ZtCrashReporter reporter;

  @override
  Widget build(BuildContext context) {
    final l = ZtL10n.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: reporter,
      builder: (context, _) {
        final reports = reporter.reports;
        final modes = [
          ZtCrashReportMode.off,
          ZtCrashReportMode.ask,
          if (reporter.canSend) ZtCrashReportMode.automatic,
        ];
        return Scaffold(
          appBar: AppBar(title: Text(l.crashReports)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.crashReportsIntro, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    _Point(icon: Icons.check, text: l.crashReportsIncluded),
                    const SizedBox(height: 8),
                    _Point(
                        icon: Icons.block, text: l.crashReportsNeverIncluded),
                  ],
                ),
              ),
              RadioGroup<ZtCrashReportMode>(
                groupValue: reporter.mode,
                onChanged: (m) => reporter.setMode(m!),
                child: Column(
                  children: [
                    for (final m in modes)
                      RadioListTile<ZtCrashReportMode>(
                        value: m,
                        title: Text(_modeLabel(l, m, reporter.canSend)),
                      ),
                  ],
                ),
              ),
              if (reporter.mode != ZtCrashReportMode.off) ...[
                Semantics(
                  header: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(l.crashReportsSaved,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                ),
                if (reports.isEmpty)
                  ListTile(title: Text(l.crashReportsNone))
                else ...[
                  for (final r in reports)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      // Code names and dates read left to right.
                      title:
                          Text(r.errorType, textDirection: TextDirection.ltr),
                      subtitle: Text('${r.day} · ${r.appVersion} · '
                          '${l.crashReportHappened(r.count)}'),
                      onTap: () => showZtCrashReport(context, reporter, r),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l.crashReportsDeleteAll),
                        onPressed: reporter.deleteAll,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );
}

/// Shows one report exactly as it would be sent, with Send (when the app
/// has a destination), Copy and Delete.
Future<void> showZtCrashReport(
    BuildContext context, ZtCrashReporter reporter, ZtCrashReport report) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l = ZtL10n.of(dialogContext);
      final messenger = ScaffoldMessenger.maybeOf(context);
      void say(String text) => messenger?.showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
      return AlertDialog(
        title: Text(l.crashReports),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.crashReportWholeReport),
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  report.toText(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              reporter.delete(report.id);
              Navigator.pop(dialogContext);
            },
            child: Text(l.delete),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report.toText()));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              say(l.crashReportCopied);
            },
            child: Text(l.copy),
          ),
          if (reporter.canSend)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await reporter.send(report.id);
                  say(l.crashReportSent);
                } on Object {
                  say(l.crashReportNotSent);
                }
              },
              child: Text(l.crashReportSend),
            ),
        ],
      );
    },
  );
}

/// For apps to call once after unlock: with "Ask me before sending" and
/// reports waiting, asks whether to send them. Does nothing otherwise.
Future<void> maybeAskToSendZtCrashReports(
    BuildContext context, ZtCrashReporter? reporter) async {
  if (reporter == null ||
      !reporter.canSend ||
      reporter.mode != ZtCrashReportMode.ask ||
      reporter.reports.isEmpty) {
    return;
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final l = ZtL10n.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: Text(l.crashReportPromptTitle),
        content: Text(l.crashReportPromptBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'no'),
              child: Text(l.crashReportDontSend)),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'view'),
              child: Text(l.crashReportView)),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'send'),
              child: Text(l.crashReportSend)),
        ],
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'no':
      reporter.deleteAll();
    case 'view':
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ZtCrashReportsScreen(reporter: reporter)));
    case 'send':
      final l = ZtL10n.of(context);
      final messenger = ScaffoldMessenger.maybeOf(context);
      final before = reporter.reports.length;
      await reporter.sendAll();
      messenger?.showSnackBar(SnackBar(
          content: Text(reporter.reports.length < before
              ? l.crashReportSent
              : l.crashReportNotSent),
          duration: const Duration(seconds: 4)));
  }
}
