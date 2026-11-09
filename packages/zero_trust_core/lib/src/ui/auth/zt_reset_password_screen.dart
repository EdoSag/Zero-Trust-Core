import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../account/password_check.dart';
import '../../core_providers.dart';
import 'zt_auth_messages.dart';
import 'zt_password_strength.dart';

/// Second half of "forgot password": opened from Supabase's reset-email deep
/// link (which signs the user in). The recovery key unlocks the data and a
/// new password is set. Other devices are signed out and the used recovery
/// key is replaced: show `ZtRecoveryKeyScreen` for the result's
/// `newRecoveryKey` before anything else.
class ZtResetPasswordScreen extends ConsumerStatefulWidget {
  const ZtResetPasswordScreen({super.key, required this.onUnlocked});

  final void Function(UnlockResult result) onUnlocked;

  @override
  ConsumerState<ZtResetPasswordScreen> createState() =>
      _ZtResetPasswordScreenState();
}

class _ZtResetPasswordScreenState extends ConsumerState<ZtResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _recoveryKey = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _recoveryKey.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Use exactly what was validated, even if a field changes meanwhile.
    final recoveryKey = _recoveryKey.text;
    final password = _password.text;
    try {
      final breached = await ztBreachedPasswordError(
          ref.read(ztBreachedPasswordCheckerProvider), password);
      if (breached != null) {
        if (mounted) setState(() => _error = breached);
        return;
      }
      final result = await ref
          .read(accountServiceProvider)
          .recover(recoveryKey: recoveryKey, newPassword: password);
      if (mounted) widget.onUnlocked(result);
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(ZtL10n.of(context).resetPassword)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(ZtL10n.of(context).enterTheRecoveryKeyYouSaved),
              const SizedBox(height: 24),
              TextFormField(
                controller: _recoveryKey,
                decoration: InputDecoration(
                    labelText: ZtL10n.of(context).recoveryKey,
                    hintText: 'ZT-XXXX-XXXX-…'),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? ZtL10n.of(context).enterYourRecoveryKey
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration:
                    InputDecoration(labelText: ZtL10n.of(context).newPassword),
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => ztValidateNewPassword(v,
                    email: ref.read(accountServiceProvider).currentEmail),
              ),
              ZtPasswordStrengthMeter(
                  controller: _password,
                  email: ref.read(accountServiceProvider).currentEmail),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                decoration: InputDecoration(
                    labelText: ZtL10n.of(context).confirmNewPassword),
                obscureText: true,
                validator: (v) => v == _password.text
                    ? null
                    : ZtL10n.of(context).passwordsDontMatch,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(ZtL10n.of(context).resetPassword),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
