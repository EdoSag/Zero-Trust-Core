import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../config/zt_app_config.dart';
import '../../core_providers.dart';
import 'zt_auth_messages.dart';

/// Sign in or create a Zero-Trust account. Identical in every app.
///
/// [onUnlocked] receives the result; when it carries a new recovery key the
/// app must show `ZtRecoveryKeyScreen` before anything else.
class ZtSignInScreen extends ConsumerStatefulWidget {
  const ZtSignInScreen({
    super.key,
    required this.onUnlocked,
    this.onForgotPassword,
  });

  final void Function(UnlockResult result) onUnlocked;
  final VoidCallback? onForgotPassword;

  @override
  ConsumerState<ZtSignInScreen> createState() => _ZtSignInScreenState();
}

class _ZtSignInScreenState extends ConsumerState<ZtSignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
    final account = ref.read(accountServiceProvider);
    try {
      final result = _creating
          ? await account.signUp(
              email: _email.text.trim(), password: _password.text)
          : await account.signIn(
              email: _email.text.trim(), password: _password.text);
      if (mounted) widget.onUnlocked(result);
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(ztAppConfigProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(config.displayName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      _creating
                          ? 'One account for every Zero-Trust app. Your password never leaves this device.'
                          : 'Sign in with your Zero-Trust account.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: ztValidateEmail,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      autofillHints: [
                        _creating
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      validator: ztValidatePassword,
                      onFieldSubmitted: (_) => _creating ? null : _submit(),
                    ),
                    if (_creating) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirm,
                        decoration: const InputDecoration(
                            labelText: 'Confirm password'),
                        obscureText: _obscure,
                        validator: (v) => v == _password.text
                            ? null
                            : 'Passwords don\'t match.',
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                      child: Text(_creating
                          ? 'I already have an account'
                          : 'Create a Zero-Trust account'),
                    ),
                    if (!_creating && widget.onForgotPassword != null)
                      TextButton(
                        onPressed: _busy ? null : widget.onForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
