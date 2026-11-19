import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../core_providers.dart';
import '../../l10n/zt_l10n.dart';
import 'zt_auth_messages.dart';

/// Asks the person holding the phone to prove it's the owner before a
/// sensitive action, however the app is set to lock: fingerprint or face
/// when biometric unlock is on, otherwise (or if they cancel that) the
/// account password. Works offline.
///
/// Returns the unlocked key on success, null when cancelled. The caller
/// owns the key and must zero it (`result.dek.fillRange(0, n, 0)`) once
/// done with it.
Future<UnlockResult?> ztConfirmIdentity(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required String action,
}) async {
  final account = ref.read(accountServiceProvider);
  try {
    if (await account.biometricsEnabled()) {
      final result = await account.unlockWithBiometrics();
      if (result != null) return result;
    }
  } on Object {
    // Biometric key gone or unavailable: the password still works.
  }
  if (!context.mounted) return null;
  return showDialog<UnlockResult>(
    context: context,
    builder: (_) =>
        _VerifyPasswordDialog(title: title, message: message, action: action),
  );
}

class _VerifyPasswordDialog extends ConsumerStatefulWidget {
  const _VerifyPasswordDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final String action;

  @override
  ConsumerState<_VerifyPasswordDialog> createState() =>
      _VerifyPasswordDialogState();
}

class _VerifyPasswordDialogState extends ConsumerState<_VerifyPasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Ignored while empty: an empty password would only run the slow key
    // derivation to fail.
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(accountServiceProvider).unlock(_password.text);
      _password.clear();
      if (mounted) {
        Navigator.pop(context, result);
      } else {
        result.dek.fillRange(0, result.dek.length, 0);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            decoration: InputDecoration(
                labelText: ZtL10n.of(context).password, errorText: _error),
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(ZtL10n.of(context).cancel)),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.action),
        ),
      ],
    );
  }
}
