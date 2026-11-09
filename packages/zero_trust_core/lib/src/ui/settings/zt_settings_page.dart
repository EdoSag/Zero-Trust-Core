import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../export/zt_data_export.dart';
import '../../export/zt_export_data_tile.dart';
import '../../attachments/attachment_cache.dart';
import '../../config/zt_preferences.dart';
import '../../config/zt_suite.dart';
import '../brand/zt_brand_mark.dart';
import 'zt_data_protection_screen.dart';
import '../../core_providers.dart';
import '../../vault/vault_controller.dart';
import '../../account/password_check.dart';
import '../auth/zt_auth_messages.dart';
import '../auth/zt_password_strength.dart';
import '../../sync/zt_local_store.dart';
import '../auth/zt_recovery_key_screen.dart';
import 'zt_sync_status_tile.dart';

/// The settings screen every Zero-Trust app shows. Sections and their order
/// are fixed so the apps feel like one product; apps add their own rows
/// through [appSection] and [backupSection].
class ZtSettingsPage extends ConsumerWidget {
  const ZtSettingsPage({
    super.key,
    required this.onSignedOut,
    this.appSection = const [],
    this.backupSection = const [],
    this.onDataExported,
    this.version,
    this.privacyPolicyUrl,
    this.termsUrl,
    this.supportUrl,
    this.onOpenUrl,
    this.showSyncStatus = false,
    this.showOtherApps = true,
  });

  /// Called after sign-out and after account deletion. Route to sign-in.
  final VoidCallback onSignedOut;

  /// App-specific rows, shown under the app's name.
  final List<Widget> appSection;

  /// Export / import rows. Hidden when empty.
  final List<Widget> backupSection;

  /// Shows "Export my data" ([ZtExportDataTile]) at the top of Backup and
  /// receives the ZIP file, usually to open the share sheet.
  final Future<void> Function(File file, ZtExport export)? onDataExported;

  final String? version;

  /// Store requirement. Each link row shows only with [onOpenUrl] set.
  final Uri? privacyPolicyUrl;

  /// Terms of use.
  final Uri? termsUrl;

  /// Help and feedback: a web page or a `mailto:` link.
  final Uri? supportUrl;

  final void Function(Uri url)? onOpenUrl;

  /// Shows [ZtSyncStatusTile] under the account. Needs the core's sync
  /// providers (`ztSyncControllerProvider`).
  final bool showSyncStatus;

  /// Lists the suite's other apps (same account) with a link to each in
  /// the store, opened through [onOpenUrl]. Hidden without [onOpenUrl].
  final bool showOtherApps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ztAppConfigProvider);
    final account = ref.watch(accountServiceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final autoLock = ref.watch(ztAutoLockProvider);
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
          if (showSyncStatus) const ZtSyncStatusTile(),
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
            subtitle: Text(_autoLockLabel(autoLock)),
            onTap: () => _pickAutoLock(context, ref, autoLock),
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
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('How your data is protected'),
            subtitle: const Text('End-to-end encryption, in plain words'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const ZtDataProtectionScreen())),
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
          const _DynamicColorTile(),
          if (backupSection.isNotEmpty || onDataExported != null) ...[
            const _Header('Backup'),
            if (onDataExported != null)
              ZtExportDataTile(onExported: onDataExported!),
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
          if (supportUrl != null && onOpenUrl != null)
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help and feedback'),
              onTap: () => onOpenUrl!(supportUrl!),
            ),
          if (privacyPolicyUrl != null && onOpenUrl != null)
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Privacy policy'),
              onTap: () => onOpenUrl!(privacyPolicyUrl!),
            ),
          if (termsUrl != null && onOpenUrl != null)
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Terms of use'),
              onTap: () => onOpenUrl!(termsUrl!),
            ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licences'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: config.displayName,
              applicationVersion: version,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: ZtBrandMark(app: ZtSuite.byId(config.appId), size: 48),
              ),
            ),
          ),
          if (showOtherApps && onOpenUrl != null) ...[
            const _Header('Other Zero-Trust apps'),
            for (final app in ZtSuite.apps)
              if (app.appId != config.appId)
                ListTile(
                  leading: ZtBrandMark(app: app, size: 40),
                  title: Text(app.fullName),
                  subtitle: Text('${app.tagline} · same account'),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => onOpenUrl!(app.playStoreUrl),
                ),
          ],
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
    if (d == null) return 'Never';
    if (d == Duration.zero) return 'Immediately when you leave the app';
    if (d.inMinutes >= 1) {
      return 'After ${d.inMinutes} min in the background or idle';
    }
    return 'After ${d.inSeconds} s in the background or idle';
  }

  static String _autoLockChoice(Duration? d) => switch (d) {
        null => 'Never',
        Duration.zero => 'Immediately',
        _ when d.inMinutes >= 1 => 'After ${d.inMinutes} min',
        _ => 'After ${d.inSeconds} s',
      };

  Future<void> _pickAutoLock(
      BuildContext context, WidgetRef ref, Duration? current) async {
    final choices = {...AutoLockController.choices, current}.toList();
    final picked = await showDialog<(Duration?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Auto-lock'),
        children: [
          RadioGroup<Duration?>(
            groupValue: current,
            onChanged: (d) => Navigator.pop(context, (d,)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in choices)
                  RadioListTile<Duration?>(
                      value: d, title: Text(_autoLockChoice(d))),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(ztAutoLockProvider.notifier).set(picked.$1);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Password changed. Your other devices were signed out.')));
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
      final key = await account.newRecoveryKey(password);
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

  /// Removes this app's local store for a deleted account. Best effort: the
  /// file is encrypted under keys that no longer exist anywhere.
  static Future<void> _deleteLocalData(WidgetRef ref, String userId) async {
    try {
      final appId = ref.read(ztAppConfigProvider).appId;
      await ZtLocalStore.deleteFiles(
          await ZtLocalStore.pathFor(appId: appId, userId: userId));
      await FileAttachmentCache.deleteFor(appId: appId, userId: userId);
    } on Object {
      // No platform storage (tests), or already gone.
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
      final userId = account.currentUserId;
      await account.deleteAccount(password: password);
      ref.read(vaultControllerProvider.notifier).lock();
      if (userId != null) await _deleteLocalData(ref, userId);
      onSignedOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ztAuthErrorMessage(e))));
      }
    }
  }
}

/// "Use wallpaper colours" (Material You). Hidden where the platform has
/// no wallpaper palette (iOS, Android before 12).
class _DynamicColorTile extends ConsumerStatefulWidget {
  const _DynamicColorTile();

  @override
  ConsumerState<_DynamicColorTile> createState() => _DynamicColorTileState();
}

class _DynamicColorTileState extends ConsumerState<_DynamicColorTile> {
  bool _available = false;

  @override
  void initState() {
    super.initState();
    DynamicColorPlugin.getCorePalette().then((p) {
      if (mounted && p != null) setState(() => _available = true);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.palette_outlined),
      title: const Text('Use wallpaper colours'),
      subtitle: const Text('Match your phone\'s theme instead of the app\'s'),
      value: ref.watch(ztDynamicColorProvider),
      onChanged: (on) => ref.read(ztDynamicColorProvider.notifier).set(on),
    );
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
            onSubmitted: (v) {
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
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
          // Ignored while empty: an empty password would only run the slow
          // key derivation to fail.
          onPressed: () {
            if (_password.text.isNotEmpty) {
              Navigator.pop(context, _password.text);
            }
          },
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
    // Use exactly what was validated, even if a field changes meanwhile.
    final current = _current.text;
    final next = _next.text;
    try {
      final breached = await ztBreachedPasswordError(
          ref.read(ztBreachedPasswordCheckerProvider), next);
      if (breached != null) {
        if (mounted) setState(() => _error = breached);
        return;
      }
      await ref
          .read(accountServiceProvider)
          .changePassword(currentPassword: current, newPassword: next);
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
              validator: (v) => ztValidateNewPassword(v,
                  email: ref.read(accountServiceProvider).currentEmail),
            ),
            ZtPasswordStrengthMeter(
                controller: _next,
                email: ref.read(accountServiceProvider).currentEmail),
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
