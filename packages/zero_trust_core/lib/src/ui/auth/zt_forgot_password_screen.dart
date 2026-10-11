import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core_providers.dart';
import 'zt_auth_messages.dart';

/// First half of "forgot password": emails a link that opens the app's
/// `ZtResetPasswordScreen`. [redirectTo] is the app's deep link.
class ZtForgotPasswordScreen extends ConsumerStatefulWidget {
  const ZtForgotPasswordScreen({super.key, this.redirectTo, this.initialEmail});

  final String? redirectTo;
  final String? initialEmail;

  @override
  ConsumerState<ZtForgotPasswordScreen> createState() =>
      _ZtForgotPasswordScreenState();
}

class _ZtForgotPasswordScreenState
    extends ConsumerState<ZtForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountServiceProvider)
          .sendPasswordReset(_email.text, redirectTo: widget.redirectTo);
      if (mounted) setState(() => _sent = true);
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
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: _sent
                ? [
                    Icon(Icons.mark_email_read_outlined,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Check ${_email.text.trim()} for a reset link. Open it on this device, '
                      'then enter your recovery key.',
                      textAlign: TextAlign.center,
                    ),
                  ]
                : [
                    const Text(
                      'Your data is encrypted with your password, so resetting it needs two '
                      'things: a link we email you, and the recovery key you saved when you '
                      'created your account.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: ztValidateEmail,
                      onFieldSubmitted: (_) => _send(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Email me a reset link'),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
