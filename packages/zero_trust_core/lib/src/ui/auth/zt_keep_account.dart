import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../account/account_service.dart';
import '../../l10n/zt_l10n.dart';
import '../settings/zt_updates_tiles.dart';
import 'zt_auth_messages.dart';

/// A deletion date as people read it ("29 November 2026"), in the app's
/// language and the phone's time zone.
String ztDeletionDate(DateTime when) =>
    DateFormat.yMMMMd().format(when.toLocal());

/// Call right after sign-in or unlock (the core's screens do). When the
/// account is set to be deleted (Z22), asks once whether to keep it, on
/// top of whatever the app shows next; then, in builds installed from
/// GitHub, says when an update is ready (S-1). Never delays opening the
/// app and never throws: the checks run in the background and are skipped
/// when the server can't be reached.
void ztCheckPendingDeletionAfterUnlock(
    BuildContext context, AccountService account) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator == null) return;
  ProviderContainer? container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } on Object {
    // No ProviderScope above (a bare test): only the deletion check runs.
  }
  unawaited(() async {
    try {
      final when = await account.pendingDeletion();
      if (when != null && navigator.mounted) {
        await ztOfferToKeepAccount(navigator.context, account, when);
      }
      if (container != null && navigator.mounted) {
        await ztCheckForUpdateAfterUnlock(navigator, container);
      }
    } on Object {
      // Best effort; the app is already open.
    }
  }());
}

/// The "Your account is set to be deleted" dialog. True when the person
/// kept the account.
Future<bool> ztOfferToKeepAccount(
    BuildContext context, AccountService account, DateTime when) async {
  final keep = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l = ZtL10n.of(context);
      return AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: Text(l.accountDeletionScheduledTitle),
        content: Text(l.accountDeletionScheduledBody(ztDeletionDate(when))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.deleteAsPlanned),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.keepMyAccount),
          ),
        ],
      );
    },
  );
  if (keep != true) return false;
  final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
  try {
    await account.keepAccount();
    messenger
        ?.showSnackBar(SnackBar(content: Text(ZtL10n.current.accountKept)));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(ztAuthErrorMessage(e))));
    return false;
  }
}

/// Settings row shown while the account is set to be deleted. Tapping it
/// offers to keep the account.
class ZtPendingDeletionTile extends StatefulWidget {
  const ZtPendingDeletionTile({super.key, required this.account});

  final AccountService account;

  @override
  State<ZtPendingDeletionTile> createState() => _ZtPendingDeletionTileState();
}

class _ZtPendingDeletionTileState extends State<ZtPendingDeletionTile> {
  DateTime? _when;

  @override
  void initState() {
    super.initState();
    widget.account.pendingDeletion().then((when) {
      if (mounted && when != null) setState(() => _when = when);
    });
  }

  @override
  Widget build(BuildContext context) {
    final when = _when;
    if (when == null) return const SizedBox.shrink();
    final error = Theme.of(context).colorScheme.error;
    final l = ZtL10n.of(context);
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: error),
      title:
          Text(l.accountDeletionScheduledTitle, style: TextStyle(color: error)),
      subtitle: Text(l.accountDeletionScheduledTile(ztDeletionDate(when))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        if (await ztOfferToKeepAccount(context, widget.account, when) &&
            mounted) {
          setState(() => _when = null);
        }
      },
    );
  }
}
