import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core_providers.dart';
import '../../l10n/zt_l10n.dart';
import '../auth/zt_auth_messages.dart';
import '../layout/zt_adaptive.dart';

/// Change the account's email (Z14), in two steps: the new address and the
/// password, then the 6-digit code emailed to the new address. Pops with
/// the new email when done.
///
/// The password stays in this screen's memory between the steps: the
/// server needs the sign-in secret for the new address in the same step as
/// the code, and it can only be derived from the password.
class ZtChangeEmailScreen extends ConsumerStatefulWidget {
  const ZtChangeEmailScreen({super.key});

  @override
  ConsumerState<ZtChangeEmailScreen> createState() =>
      _ZtChangeEmailScreenState();
}

class _ZtChangeEmailScreenState extends ConsumerState<ZtChangeEmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final email = _email.text.trim();
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
          throw ArgumentError(ZtL10n.current.errEmailInvalid);
        }
        if (_password.text.isEmpty) return;
        await ref
            .read(accountServiceProvider)
            .startEmailChange(password: _password.text, newEmail: email);
        if (mounted) {
          setState(() {
            _codeSent = true;
            _code.clear();
          });
        }
      });

  Future<void> _confirm() => _run(() async {
        if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) return;
        final email = await ref.read(accountServiceProvider).finishEmailChange(
              password: _password.text,
              newEmail: _email.text.trim(),
              code: _code.text,
            );
        _password.clear();
        if (mounted) Navigator.pop(context, email);
      });

  @override
  Widget build(BuildContext context) {
    final l = ZtL10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.changeEmail)),
      body: ZtReadableListView(
        maxWidth: ZtLayout.formWidth,
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.changeEmailIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          TextField(
            key: const Key('zt-new-email'),
            controller: _email,
            enabled: !_codeSent && !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textDirection: TextDirection.ltr,
            autofocus: true,
            decoration: InputDecoration(labelText: l.newEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('zt-current-password'),
            controller: _password,
            enabled: !_codeSent && !_busy,
            obscureText: true,
            decoration: InputDecoration(labelText: l.currentPassword),
            onSubmitted: (_) => _sendCode(),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 24),
            Text(l.enterEmailCode(_email.text.trim()),
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              key: const Key('zt-email-code'),
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.emailCode),
              onSubmitted: (_) => _confirm(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _confirm : _sendCode),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_codeSent ? l.changeEmailConfirm : l.sendCode),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(l.sendNewCode),
            ),
          ],
        ],
      ),
    );
  }
}
