import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_backend.dart';
import '../../account/account_service.dart';
import '../../account/password_check.dart';
import '../../config/zt_app_config.dart';
import '../../core_providers.dart';
import '../../config/zt_suite.dart';
import '../brand/zt_brand_mark.dart';
import 'zt_auth_messages.dart';
import 'zt_password_strength.dart';

/// Sign in or create a Zero-Trust account. Identical in every app.
///
/// [onUnlocked] receives the result; when it carries a new recovery key the
/// app must show `ZtRecoveryKeyScreen` before anything else.
///
/// When the project requires email confirmation, creating an account sends
/// the link and switches to sign-in; signing in before confirming offers to
/// resend it.
class ZtSignInScreen extends ConsumerStatefulWidget {
  const ZtSignInScreen({
    super.key,
    required this.onUnlocked,
    this.onForgotPassword,
    this.emailRedirectTo,
    this.offerBiometrics = false,
  });

  final void Function(UnlockResult result) onUnlocked;
  final VoidCallback? onForgotPassword;

  /// Where the confirmation link opens (the app's deep link). Defaults to
  /// the project's Site URL.
  final String? emailRedirectTo;

  /// After signing in, offer to turn on fingerprint or face unlock when the
  /// device has it and it isn't on yet (part of the shared onboarding).
  final bool offerBiometrics;

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
  String? _info;
  bool _canResend = false;

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
      _info = null;
      _canResend = false;
    });
    final account = ref.read(accountServiceProvider);
    // What was validated is what gets used, even if a field changes while
    // the breach check or the KDF is running.
    final creating = _creating;
    final email = _email.text.trim();
    final password = _password.text;
    try {
      if (creating) {
        final breached = await ztBreachedPasswordError(
            ref.read(ztBreachedPasswordCheckerProvider), password);
        if (breached != null) {
          if (mounted) setState(() => _error = breached);
          return;
        }
      }
      final result = creating
          ? await account.signUp(
              email: email,
              password: password,
              redirectTo: widget.emailRedirectTo)
          : await account.signIn(email: email, password: password);
      if (widget.offerBiometrics) await _offerBiometrics(result);
      if (mounted) widget.onUnlocked(result);
    } on EmailConfirmationSent catch (e) {
      if (mounted) {
        setState(() {
          _info = ztAuthErrorMessage(e);
          _creating = false;
          _canResend = true;
          _confirm.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ztAuthErrorMessage(e);
          _canResend = e is EmailNotConfirmed;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Never blocks sign-in: any failure just leaves biometrics off.
  Future<void> _offerBiometrics(UnlockResult result) async {
    final account = ref.read(accountServiceProvider);
    try {
      if (!await account.biometricsAvailable() ||
          await account.biometricsEnabled() ||
          !mounted) {
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.fingerprint),
          title: const Text('Unlock with biometrics?'),
          content: const Text('Use your fingerprint or face to open the app '
              'on this phone. You can change this in Settings.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn on')),
          ],
        ),
      );
      if (yes == true) await account.enableBiometricsAfterSignIn(result);
    } on Object {
      // Stays off; the Settings switch can turn it on later.
    }
  }

  Future<void> _resend() async {
    if (ztValidateEmail(_email.text) != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(accountServiceProvider).resendConfirmation(
          _email.text.trim(),
          redirectTo: widget.emailRedirectTo);
      if (mounted) {
        setState(() {
          _error = null;
          _info = 'Sent again. Check your inbox and spam folder.';
        });
      }
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
                    Center(child: ZtBrandMark(app: ZtSuite.byId(config.appId))),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(config.displayName,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall),
                    ),
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
                      // Accounts from pre-core app versions may have shorter passwords;
                      // they must still be able to sign in and upgrade.
                      validator: (v) => _creating
                          ? ztValidateNewPassword(v, email: _email.text.trim())
                          : ((v ?? '').isEmpty ? 'Enter your password.' : null),
                      onFieldSubmitted: (_) => _creating ? null : _submit(),
                    ),
                    if (_creating) ...[
                      ZtPasswordStrengthMeter(
                          controller: _password, email: _email.text.trim()),
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
                    // Live regions: screen readers announce these when
                    // they appear, since focus stays on the button.
                    if (_info != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                          liveRegion: true,
                          child: Text(_info!, textAlign: TextAlign.center)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error),
                            textAlign: TextAlign.center),
                      ),
                    ],
                    if (_canResend)
                      TextButton(
                        onPressed: _busy ? null : _resend,
                        child: const Text('Resend confirmation email'),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: _creating
                                      ? 'Creating account'
                                      : 'Signing in'))
                          : Text(_creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                                _info = null;
                                _canResend = false;
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
