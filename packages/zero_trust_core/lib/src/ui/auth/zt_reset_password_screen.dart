import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../core_providers.dart';
import 'zt_auth_messages.dart';

/// Second half of "forgot password": opened from Supabase's reset-email deep
/// link (which signs the user in). The recovery key unlocks the data and a
/// new password is set.
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
    try {
      final result = await ref
          .read(accountServiceProvider)
          .recover(recoveryKey: _recoveryKey.text, newPassword: _password.text);
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
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                  'Enter the recovery key you saved when you created your account, '
                  'then choose a new password.'),
              const SizedBox(height: 24),
              TextFormField(
                controller: _recoveryKey,
                decoration: const InputDecoration(
                    labelText: 'Recovery key', hintText: 'ZT-XXXX-XXXX-…'),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Enter your recovery key.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'New password'),
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: ztValidatePassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password'),
                obscureText: true,
                validator: (v) =>
                    v == _password.text ? null : 'Passwords don\'t match.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('Reset password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
