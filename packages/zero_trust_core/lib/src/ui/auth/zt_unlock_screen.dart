import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../config/zt_app_config.dart';
import '../../core_providers.dart';
import '../../config/zt_suite.dart';
import '../../handoff/zt_sign_in_handoff.dart';
import '../brand/zt_brand_mark.dart';
import 'zt_auth_messages.dart';
import 'zt_keep_account.dart';
import 'zt_sign_in_handoff_ui.dart';

/// Unlock an already signed-in session (app relaunch, after auto-lock).
/// Works offline, and offers biometrics when the user turned them on.
///
/// When the user chose "Never, even after closing the app" in Auto-lock, it
/// first opens the vault with the key kept on the phone, without asking
/// (see `AccountService.resumeSession`). Otherwise it behaves as before.
class ZtUnlockScreen extends ConsumerStatefulWidget {
  const ZtUnlockScreen({
    super.key,
    required this.onUnlocked,
    this.email,
    this.onSignOut,
    this.onForgotPassword,
    this.autoPromptBiometrics = true,
  });

  final void Function(UnlockResult result) onUnlocked;
  final String? email;
  final VoidCallback? onSignOut;

  /// Shows "Forgot password?"; route to `ZtResetPasswordScreen`.
  final VoidCallback? onForgotPassword;

  /// Show the biometric prompt as soon as the screen opens.
  final bool autoPromptBiometrics;

  @override
  ConsumerState<ZtUnlockScreen> createState() => _ZtUnlockScreenState();
}

class _ZtUnlockScreenState extends ConsumerState<ZtUnlockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _biometrics = false;
  String? _error;
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final kept = await ref.read(accountServiceProvider).resumeSession();
    if (!mounted) {
      kept?.dek.fillRange(0, kept.dek.length, 0);
      return;
    }
    if (kept != null) {
      _done(kept);
      return;
    }
    // Focused only now, so the keyboard doesn't flash up for a vault that
    // opens on its own.
    _passwordFocus.requestFocus();
    await _checkBiometrics();
  }

  /// Opens the app, then (in the background) offers to keep an account
  /// that is set to be deleted.
  void _done(UnlockResult result) {
    ztCheckPendingDeletionAfterUnlock(
        context, ref.read(accountServiceProvider));
    widget.onUnlocked(result);
  }

  Future<void> _checkBiometrics() async {
    final enabled = await ref.read(accountServiceProvider).biometricsEnabled();
    if (!mounted || !enabled) return;
    setState(() => _biometrics = true);
    if (widget.autoPromptBiometrics) await _unlockWithBiometrics();
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(accountServiceProvider).unlockWithBiometrics();
      if (result != null && mounted) _done(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ztAuthErrorMessage(e);
          _biometrics = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(accountServiceProvider).unlock(_password.text);
      _password.clear();
      if (mounted) _done(result);
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(ztAppConfigProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: ZtBrandMark(
                          app: ZtSuite.byId(config.appId),
                          icon: Icons.lock_outline)),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                        ZtL10n.of(context).appIsLocked(config.displayName),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                  ),
                  if (widget.email != null) ...[
                    const SizedBox(height: 8),
                    Text(widget.email!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 32),
                  TextField(
                    controller: _password,
                    decoration: InputDecoration(
                        labelText: ZtL10n.of(context).password,
                        errorText: _error),
                    obscureText: true,
                    focusNode: _passwordFocus,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: _busy
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: ZtL10n.of(context).unlocking))
                        : Text(ZtL10n.of(context).unlock),
                  ),
                  if (widget.onForgotPassword != null)
                    TextButton(
                        onPressed: _busy ? null : widget.onForgotPassword,
                        child: Text(ZtL10n.of(context).forgotPasswordQuestion)),
                  if (_biometrics) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(ZtL10n.of(context).unlockWithBiometrics),
                    ),
                  ],
                  ZtHandoffButton(
                    mode: ZtHandoffMode.unlock,
                    enabled: !_busy,
                    onGrant: (grant) async => _done(ref
                        .read(accountServiceProvider)
                        .unlockWithHandoff(grant)),
                    onError: (message) => setState(() => _error = message),
                  ),
                  if (widget.onSignOut != null)
                    TextButton(
                        onPressed: widget.onSignOut,
                        child: Text(ZtL10n.of(context).signOut)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
