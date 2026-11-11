import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../attachments/attachment_providers.dart';
import '../attachments/zt_attachments.dart';
import '../config/zt_app_config.dart';
import '../platform/zt_platform.dart';
import '../sync/sync_providers.dart';
import '../ui/auth/zt_auth_messages.dart';
import 'zt_data_export.dart';

/// Saves an export where [ZtExportDataTile] hands it to the app: the app's
/// temporary folder unless overridden (tests).
final ztExportFileWriterProvider =
    Provider<Future<File> Function(ZtExport export)>((ref) => (export) async {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/${export.fileName}');
          await file.writeAsBytes(export.zip, flush: true);
          return file;
        });

/// "Export my data" for the shared settings screen. Warns that the export
/// isn't encrypted, builds it from this device's store (see
/// [ZtDataExporter]), saves it with [ztExportFileWriterProvider] and passes
/// the file to [onExported], which usually opens the share sheet. On the
/// web the zip is downloaded by the browser instead and [onExported] isn't
/// called.
class ZtExportDataTile extends ConsumerStatefulWidget {
  const ZtExportDataTile({super.key, required this.onExported});

  final Future<void> Function(File file, ZtExport export) onExported;

  @override
  ConsumerState<ZtExportDataTile> createState() => _ZtExportDataTileState();
}

class _ZtExportDataTileState extends ConsumerState<ZtExportDataTile> {
  bool _busy = false;

  Future<void> _export() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ZtL10n.of(context).exportMyDataQuestion),
        content: Text(ZtL10n.of(context).youGetOneZipFileWith),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ZtL10n.of(context).cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ZtL10n.of(context).export)),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = await ref.read(ztLocalStoreProvider.future);
      ZtAttachments? attachments;
      try {
        // A failing provider is retried, so `.future` may never complete.
        attachments = await ref
            .read(ztAttachmentsProvider.future)
            .timeout(const Duration(seconds: 5));
      } on Object {
        attachments = null; // App without attachments, or no storage.
      }
      final export = await ZtDataExporter(
        appId: ref.read(ztAppConfigProvider).appId,
        store: store,
        attachments: attachments,
      ).build();
      if (kIsWeb) {
        await ztDownloadFile(export.fileName, export.zip);
      } else {
        final file = await ref.read(ztExportFileWriterProvider)(export);
        await widget.onExported(file, export);
      }
      if (export.missingAttachments.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
            content: Text(ZtL10n.current
                .attachmentsNotIncluded(export.missingAttachments.length))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ztErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(ZtL10n.of(context).exportMyData),
      subtitle: Text(ZtL10n.of(context).aZipOfEverythingInThis),
      trailing: _busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, semanticsLabel: ZtL10n.of(context).exporting))
          : null,
      enabled: !_busy,
      onTap: _export,
    );
  }
}
