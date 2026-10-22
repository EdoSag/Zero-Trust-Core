import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../core_providers.dart';
import '../../vault/vault_controller.dart';
import '../auth/zt_auth_messages.dart';
import '../auth/zt_recovery_key_screen.dart';

/// The settings screen every Zero-Trust app shows. Sections and their order
/// are fixed so the apps feel like one product; apps add their own rows
/// through [appSection] and [backupSection].
class ZtSettingsPage extends ConsumerWidget {
  const ZtSettingsPage({
    super.key,
    required this.onSignedOut,
    this.appSection = const [],
    this.backupSection = const [],
    this.version,
    this.privacyPolicyUrl,
    this.onOpenUrl,
  });

  /// Called after sign-out and after account deletion. Route to sign-in.
  final VoidCallback onSignedOut;

  /// App-specific rows, shown under the app's name.
  final List<Widget> appSection;

  /// Export / import rows. Hidden when empty.
  final List<Widget> backupSection;

  final String? version;
  final Uri? privacyPolicyUrl;
  final void Function(Uri url)? onOpenUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ztAppConfigProvider);
    final account = ref.watch(accountServiceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Account'),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(account.currentEmail ?? 'Not signed in'),
            subtitle: const Text('One account for every Zero-Trust app'),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            onTap: () => _changePassword(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              ref.read(vaultControllerProvider.notifier).lock();
              await account.signOut();
              onSignedOut();
            },
          ),
          const _Header('Security'),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Auto-lock'),
            subtitle: Text(_autoLockLabel(config.autoLockAfter)),
          ),
          const _BiometricTile(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: () => ref.read(vaultControllerProvider.notifier).lock(),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('New recovery key'),
            subtitle: const Text('Your current recovery key will stop working'),
            onTap: () => _newRecoveryKey(context, ref),
          ),
          const _Header('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
            child: const Column(
              children: [
                RadioListTile(
                    value: ThemeMode.system, title: Text('System default')),
                RadioListTile(value: ThemeMode.light, title: Text('Light')),
                RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
              ],
            ),
          ),
          if (backupSection.isNotEmpty) ...[
            const _Header('Backup'),
            ...backupSection,
          ],
          if (appSection.isNotEmpty) ...[
            _Header(config.displayName),
            ...appSection,
          ],
          const _Header('About'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(config.displayName),
            subtitle: Text([
              if (version != null) 'Version $version',
              'End-to-end encrypted. We can\'t read your data.',
            ].join(' · ')),
          ),
          if (privacyPolicyUrl != null && onOpenUrl != null)
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Privacy policy'),
              onTap: () => onOpenUrl!(privacyPolicyUrl!),
            ),
          const _Header('Danger zone'),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: theme.colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Deletes your data in every Zero-Trust app'),
            onTap: () => _deleteAccount(context, ref),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _autoLockLabel(Duration? d) {
    if (d == null) return 'Off';
    if (d.inMinutes >= 1) {
      return 'After ${d.inMinutes} min in the background or idle';
    }
    return 'After ${d.inSeconds} s in the background or idle';
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed')));
    }
  }

  Future<void> _newRecoveryKey(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(
        title: 'New recovery key',
        message:
            'Enter your password. Your current recovery key will stop working.',
        action: 'Continue',
      ),
    );
    if (password == null || !context.mounted) return;
    final account = ref.read(accountServiceProvider);
    try {
      final unlocked = await account.unlock(password);
      final key = await account.rotateRecoveryKey(unlocked.dek);
      unlocked.dek.fillRange(0, unlocked.dek.length, 0);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => ZtRecoveryKeyScreen(
          recoveryKey: key,
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ztAuthErrorMessage(e))));
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(
        title: 'Delete account?',
        message: 'This permanently deletes your account and your data in every '
            'Zero-Trust app. It can\'t be undone.',
        action: 'Delete',
        destructive: true,
      ),
    );
    if (password == null || !context.mounted) return;
    final account = ref.read(accountServiceProvider);
    try {
      // Re-check the password so an unattended unlocked phone can't do this.
      final unlocked = await account.unlock(password);
      unlocked.dek.fillRange(0, unlocked.dek.length, 0);
      await account.deleteAccount();
      ref.read(vaultControllerProvider.notifier).lock();
      onSignedOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ztAuthErrorMessage(e))));
      }
    }
  }
}

/// Turns biometric unlock on (with the password) or off. Hidden on devices
/// without enrolled biometrics.
class _BiometricTile extends ConsumerStatefulWidget {
  const _BiometricTile();

  @override
  ConsumerState<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends ConsumerState<_BiometricTile> {
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = ref.read(accountServiceProvider);
    final available = await account.biometricsAvailable();
    final enabled = available && await account.biometricsEnabled();
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
      });
    }
  }

  Future<void> _toggle(bool on) async {
    final account = ref.read(accountServiceProvider);
    if (!on) {
      await account.disableBiometrics();
      if (mounted) setState(() => _enabled = false);
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(
        title: 'Unlock with biometrics',
        message: 'Enter your password to turn on fingerprint or face unlock '
            'on this device.',
        action: 'Turn on',
      ),
    );
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await account.enableBiometrics(password);
      if (mounted) setState(() => _enabled = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ztAuthErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Unlock with biometrics'),
      subtitle: const Text('Fingerprint or face, on this device only'),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Returns the entered password, or null when cancelled.
class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({
    required this.title,
    required this.message,
    required this.action,
    this.destructive = false,
  });

  final String title;
  final String message;
  final String action;
  final bool destructive;

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
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
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: error)
              : null,
          onPressed: () => Navigator.pop(context, _password.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
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
      await ref.read(accountServiceProvider).changePassword(
          currentPassword: _current.text, newPassword: _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ztAuthErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              decoration: const InputDecoration(labelText: 'Current password'),
              obscureText: true,
            ),
            TextFormField(
              controller: _next,
              decoration: const InputDecoration(labelText: 'New password'),
              obscureText: true,
              validator: ztValidatePassword,
            ),
            TextFormField(
              controller: _confirm,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              obscureText: true,
              validator: (v) =>
                  v == _next.text ? null : 'Passwords don\'t match.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Change')),
      ],
    );
  }
}
