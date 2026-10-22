import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_service.dart';
import '../../config/zt_app_config.dart';
import '../../core_providers.dart';
import 'zt_auth_messages.dart';

/// Unlock an already signed-in session (app relaunch, after auto-lock).
/// Works offline, and offers biometrics when the user turned them on.
class ZtUnlockScreen extends ConsumerStatefulWidget {
  const ZtUnlockScreen({
    super.key,
    required this.onUnlocked,
    this.email,
    this.onSignOut,
    this.autoPromptBiometrics = true,
  });

  final void Function(UnlockResult result) onUnlocked;
  final String? email;
  final VoidCallback? onSignOut;

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

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
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
      if (result != null && mounted) widget.onUnlocked(result);
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
                  Icon(Icons.lock_outline,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('${config.displayName} is locked',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall),
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
                        labelText: 'Password', errorText: _error),
                    obscureText: true,
                    autofocus: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: const Text('Unlock'),
                  ),
                  if (_biometrics) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with biometrics'),
                    ),
                  ],
                  if (widget.onSignOut != null)
                    TextButton(
                        onPressed: widget.onSignOut,
                        child: const Text('Sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
