import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attachments/attachment_providers.dart';
import '../config/zt_app_config.dart';
import '../config/zt_suite.dart';
import '../core_providers.dart';
import '../l10n/zt_l10n.dart';
import '../platform/zt_platform.dart';
import '../sync/sync_providers.dart';
import '../ui/auth/zt_auth_messages.dart';
import '../ui/auth/zt_confirm_identity.dart';
import 'zt_backup.dart';

/// How the app saves and opens backup files. Core has no file picker of its
/// own, so each app gives one (usually `file_picker`):
///
/// ```dart
/// ztBackupFilesProvider.overrideWithValue(ZtBackupFiles(
///   save: (name, bytes) async =>
///       await FilePicker.platform.saveFile(fileName: name, bytes: bytes) !=
///       null,
///   pick: () async => (await FilePicker.platform.pickFiles(withData: true))
///       ?.files.single.bytes,
/// )),
/// ```
class ZtBackupFiles {
  const ZtBackupFiles({required this.save, this.pick});

  /// Saves [bytes] where the user chooses. False when they cancel.
  final Future<bool> Function(String fileName, Uint8List bytes) save;

  /// The chosen file's bytes, or null when cancelled. Without it there is
  /// no "Restore from a backup".
  final Future<Uint8List?> Function()? pick;
}

/// Null hides the backup rows. On the web the browser downloads the file.
final ztBackupFilesProvider = Provider<ZtBackupFiles?>((ref) => kIsWeb
    ? ZtBackupFiles(save: (name, bytes) async {
        await ztDownloadFile(name, bytes);
        return true;
      })
    : null);

/// "Back up everything" and "Restore from a backup" for the shared settings
/// screen (S-5). See [ZtBackup].
class ZtBackupTiles extends ConsumerStatefulWidget {
  const ZtBackupTiles({super.key});

  @override
  ConsumerState<ZtBackupTiles> createState() => _ZtBackupTilesState();
}

class _ZtBackupTilesState extends ConsumerState<ZtBackupTiles> {
  bool _busy = false;
  String? _progress;

  String _appName(String app) => ZtSuite.byId(app)?.name ?? app;

  void _onApp(String? text) {
    if (mounted) setState(() => _progress = text);
  }

  Future<void> _backUp(ZtBackupFiles files) async {
    final l = ZtL10n.of(context);
    final password = await showDialog<String>(
        context: context, builder: (_) => const _NewBackupPasswordDialog());
    if (password == null || !mounted) return;
    final proof = await ztConfirmIdentity(
      context,
      ref,
      title: l.backUpEverything,
      message: l.enterYourPasswordToBackUp,
      action: l.backUp,
    );
    if (proof == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final backup = await ZtBackup.create(
        dek: proof.dek,
        password: password,
        backend: ref.read(ztSyncBackendProvider),
        files: ref.read(ztAttachmentBackendProvider),
        userId: ref.read(accountServiceProvider).currentUserId,
        sourceApp: ref.read(ztAppConfigProvider).dataAppId,
        onApp: (app) => _onApp(ZtL10n.current.backingUp(_appName(app))),
      );
      _onApp(null);
      final saved = await files.save(backup.fileName, backup.bytes);
      if (!saved) return;
      final c = backup.contents;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text([
          ZtL10n.current.backupSaved(c.itemCount, c.apps.length),
          if (c.missingFiles > 0)
            ZtL10n.current.backupFilesMissing(c.missingFiles),
        ].join(' ')),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ztErrorMessage(e))));
    } finally {
      proof.dek.fillRange(0, proof.dek.length, 0);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _restore(Future<Uint8List?> Function() pick) async {
    final l = ZtL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final Uint8List? bytes;
    try {
      bytes = await pick();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ztErrorMessage(e))));
      return;
    }
    if (bytes == null || !mounted) return;
    try {
      ZtBackup.checkHeader(bytes);
    } on NotABackup catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ztBackupErrorMessage(e))));
      return;
    }
    final contents = await showDialog<ZtBackupContents>(
        context: context, builder: (_) => _OpenBackupDialog(bytes: bytes!));
    if (contents == null || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = ZtL10n.of(context);
        return AlertDialog(
          title: Text(l.restoreBackupQuestion),
          content: Text(l.restoreBackupSummary(
            MaterialLocalizations.of(context)
                .formatMediumDate(contents.createdAt.toLocal()),
            contents.itemCount,
            contents.apps.map(_appName).join(', '),
          )),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.restore)),
          ],
        );
      },
    );
    if (go != true || !mounted) return;
    final proof = await ztConfirmIdentity(
      context,
      ref,
      title: l.restoreFromBackup,
      message: l.enterYourPasswordToRestore,
      action: l.restore,
    );
    if (proof == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ZtBackup.restore(
        contents: contents,
        dek: proof.dek,
        backend: ref.read(ztSyncBackendProvider),
        deviceId: await ref.read(ztDeviceIdProvider.future),
        files: ref.read(ztAttachmentBackendProvider),
        userId: ref.read(accountServiceProvider).currentUserId,
        onApp: (app) => _onApp(ZtL10n.current.restoring(_appName(app))),
      );
      // This app sees its restored items now; the others on their next
      // sync.
      try {
        await ref.read(ztSyncControllerProvider.notifier).syncNow();
      } on Object {
        // They arrive with the next sync anyway.
      }
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
            ZtL10n.current.backupRestored(result.restored, result.skipped)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ztErrorMessage(e))));
    } finally {
      proof.dek.fillRange(0, proof.dek.length, 0);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(ztBackupFilesProvider);
    if (files == null) return const SizedBox.shrink();
    final l = ZtL10n.of(context);
    final pick = files.pick;
    final spinner = SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, semanticsLabel: _progress ?? l.backUp));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const Key('zt-backup'),
          leading: const Icon(Icons.backup_outlined),
          title: Text(l.backUpEverything),
          subtitle: Text(_progress ?? l.backUpEverythingSubtitle),
          trailing: _busy ? spinner : null,
          enabled: !_busy,
          onTap: () => _backUp(files),
        ),
        if (pick != null)
          ListTile(
            key: const Key('zt-restore'),
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(l.restoreFromBackup),
            subtitle: Text(l.restoreFromBackupSubtitle),
            enabled: !_busy,
            onTap: () => _restore(pick),
          ),
      ],
    );
  }
}

/// The message for a backup that can't be opened.
String ztBackupErrorMessage(Object e) => switch (e) {
      NotABackup(newerVersion: true) => ZtL10n.current.backupFromNewerVersion,
      NotABackup() => ZtL10n.current.notABackupFile,
      WrongBackupPassword() => ZtL10n.current.wrongBackupPassword,
      BackupDamaged() => ZtL10n.current.backupDamaged,
      _ => ztErrorMessage(e),
    };

class _NewBackupPasswordDialog extends StatefulWidget {
  const _NewBackupPasswordDialog();

  @override
  State<_NewBackupPasswordDialog> createState() =>
      _NewBackupPasswordDialogState();
}

class _NewBackupPasswordDialogState extends State<_NewBackupPasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;
  String? _repeatError;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final l = ZtL10n.of(context);
    setState(() {
      _error = _password.text.length < ZtBackup.minPasswordLength
          ? l.useAtLeast12
          : null;
      _repeatError = _error == null && _repeat.text != _password.text
          ? l.passwordsDontMatch
          : null;
    });
    if (_error == null && _repeatError == null) {
      Navigator.pop(context, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = ZtL10n.of(context);
    return AlertDialog(
      title: Text(l.chooseBackupPassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.backupPasswordExplained),
            const SizedBox(height: 16),
            TextField(
              key: const Key('zt-backup-password'),
              controller: _password,
              decoration: InputDecoration(
                  labelText: l.backupPassword, errorText: _error),
              obscureText: true,
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('zt-backup-password-repeat'),
              controller: _repeat,
              decoration: InputDecoration(
                  labelText: l.repeatBackupPassword, errorText: _repeatError),
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _submit, child: Text(l.backUp)),
      ],
    );
  }
}

/// Asks for the backup password and opens the backup with it.
class _OpenBackupDialog extends StatefulWidget {
  const _OpenBackupDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_OpenBackupDialog> createState() => _OpenBackupDialogState();
}

class _OpenBackupDialogState extends State<_OpenBackupDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final contents = await ZtBackup.open(widget.bytes, _password.text);
      if (mounted) Navigator.pop(context, contents);
    } catch (e) {
      if (mounted) setState(() => _error = ztBackupErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = ZtL10n.of(context);
    return AlertDialog(
      title: Text(l.enterBackupPassword),
      content: TextField(
        key: const Key('zt-open-backup-password'),
        controller: _password,
        decoration:
            InputDecoration(labelText: l.backupPassword, errorText: _error),
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.cancel)),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.openBackup),
        ),
      ],
    );
  }
}
