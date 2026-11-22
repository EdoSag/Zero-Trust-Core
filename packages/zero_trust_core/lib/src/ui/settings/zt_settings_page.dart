import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../export/zt_data_export.dart';
import '../../export/zt_export_data_tile.dart';
import '../../attachments/attachment_cache.dart';
import '../../attachments/database_attachment_cache.dart';
import '../../config/zt_language.dart';
import '../../config/zt_preferences.dart';
import '../../config/zt_suite.dart';
import '../../crash/zt_crash_reporter.dart';
import '../brand/zt_brand_mark.dart';
import 'zt_crash_reports_screen.dart';
import 'zt_data_protection_screen.dart';
import '../../core_providers.dart';
import '../../vault/vault_controller.dart';
import '../../account/biometric_key_store.dart';
import '../../account/password_check.dart';
import '../auth/zt_confirm_identity.dart';
import '../auth/zt_auth_messages.dart';
import '../auth/zt_password_strength.dart';
import '../../platform/zt_capabilities.dart';
import '../../platform/zt_platform.dart';
import '../../sync/zt_local_store.dart';
import '../auth/zt_recovery_key_screen.dart';
import 'zt_plan_tile.dart';
import 'zt_storage_tile.dart';
import 'zt_sync_status_tile.dart';

/// Privacy policy every Zero-Trust app links to from Settings.
final Uri ztPrivacyPolicyUrl = Uri.parse('https://zerotrust.bz/privacy/');

/// Terms of use every Zero-Trust app links to from Settings.
final Uri ztTermsUrl = Uri.parse('https://zerotrust.bz/terms/');

/// Help page every Zero-Trust app links to from Settings.
final Uri ztSupportUrl = Uri.parse('https://zerotrust.bz/support/');

/// What "Sign out and remove data from this browser" runs once the account
/// is signed out: it empties this site's browser storage and loads the page
/// again, so nothing stays in memory either. Tests override it.
final ztBrowserWipeProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ztWipeBrowserStorage();
    ztReloadPage();
  },
);

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
    this.showStorageUsage = false,
    this.showPlan = false,
    this.onOpenPlans,
    this.showOtherApps = true,
    this.showSponsor = true,
    this.accountOptional = false,
    this.onSignIn,
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
  /// Defaults to [ztPrivacyPolicyUrl] on zerotrust.bz.
  final Uri? privacyPolicyUrl;

  /// Terms of use. Defaults to [ztTermsUrl].
  final Uri? termsUrl;

  /// Help and feedback: a web page or a `mailto:` link. Defaults to
  /// [ztSupportUrl].
  final Uri? supportUrl;

  final void Function(Uri url)? onOpenUrl;

  /// Shows [ZtSyncStatusTile] under the account. Needs the core's sync
  /// providers (`ztSyncControllerProvider`).
  final bool showSyncStatus;

  /// Shows [ZtStorageTile] (how much of the account's server storage is
  /// used) under the account. Reads `zt_my_storage()`, core 0.9.
  final bool showStorageUsage;

  /// Shows [ZtPlanTile] (the account's plan) under the account. Reads
  /// `zt_my_plan()`, core 0.11.
  final bool showPlan;

  /// Opens the app's plans screen from the plan row. Leave null where the
  /// build may not sell (see [ZtPlanTile]).
  final VoidCallback? onOpenPlans;

  /// Lists the suite's other apps (same account) with a link to each in
  /// the store, opened through [onOpenUrl]. Hidden without [onOpenUrl].
  final bool showOtherApps;

  /// Shows "Support the project" (GitHub Sponsors) in About. It appears
  /// only with [onOpenUrl] set and only in builds whose
  /// [ZtAppConfig.channel] allows outside payments (direct APKs), because
  /// Google Play and the App Store forbid such links in store builds.
  final bool showSponsor;

  /// For an app that also works without an account (ZT Clock). While
  /// nobody is signed in, the rows that need an account (password, sign
  /// out, sync, plan, storage, lock, recovery key, export, delete account)
  /// are hidden, and Appearance, the app's own rows and About stay.
  final bool accountOptional;

  /// With [accountOptional] and nobody signed in: shows "Sign in or create
  /// an account" under Account and opens the app's sign-in from it. Leave
  /// null to show no Account section while signed out.
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ztAppConfigProvider);
    final account = ref.watch(accountServiceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(ztLanguageProvider);
    final autoLock = ref.watch(ztAutoLockProvider);
    final stayUnlocked = ref.watch(ztStayUnlockedProvider);
    final caps = ref.watch(ztCapabilitiesProvider);
    final theme = Theme.of(context);
    // An app that works without an account, and nobody is signed in.
    final signedOut = accountOptional && account.currentEmail == null;

    return Scaffold(
      appBar: AppBar(title: Text(ZtL10n.of(context).settings)),
      body: ListView(
        children: [
          if (signedOut && onSignIn != null) ...[
            _Header(ZtL10n.of(context).account),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(ZtL10n.of(context).signInOrCreateAccount),
              subtitle: Text(ZtL10n.of(context).signInToBackUpAndSync),
              trailing: const Icon(Icons.chevron_right),
              onTap: onSignIn,
            ),
          ],
          if (!signedOut) ...[
            _Header(ZtL10n.of(context).account),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title:
                  Text(account.currentEmail ?? ZtL10n.of(context).notSignedIn),
              subtitle: Text(ZtL10n.of(context).oneAccountForEveryApp),
            ),
            if (showSyncStatus) const ZtSyncStatusTile(),
            if (showPlan) ZtPlanTile(onTap: onOpenPlans),
            if (showStorageUsage) const ZtStorageTile(),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(ZtL10n.of(context).changePassword),
              onTap: () => _changePassword(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(ZtL10n.of(context).signOut),
              onTap: () async {
                ref.read(vaultControllerProvider.notifier).lock();
                await account.signOut();
                onSignedOut();
              },
            ),
            if (caps.browserSession)
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(ZtL10n.of(context).signOutAndRemoveData),
                subtitle: Text(ZtL10n.of(context).forSharedOrPublicComputers),
                onTap: () => _signOutAndWipe(context, ref),
              ),
            _Header(ZtL10n.of(context).security),
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(ZtL10n.of(context).autoLock),
              subtitle: Text(!stayUnlocked
                  ? _autoLockLabel(autoLock)
                  : caps.browserSession
                      ? ZtL10n.of(context).neverRememberedOnThisBrowser
                      : ZtL10n.of(context).neverStaysOpenAfterClosing),
              onTap: () => _pickAutoLock(context, ref, autoLock, stayUnlocked),
            ),
            if (caps.browserSession)
              SwitchListTile(
                secondary: const Icon(Icons.bookmark_added_outlined),
                title: Text(ZtL10n.of(context).rememberOnThisBrowser),
                subtitle: Text(stayUnlocked
                    ? ZtL10n.of(context).rememberOnThisBrowserOn
                    : ZtL10n.of(context).rememberOnThisBrowserOff),
                value: stayUnlocked,
                onChanged: (on) => on
                    ? _turnOnStayUnlocked(context, ref)
                    : _turnOffStayUnlocked(ref),
              ),
            const _BiometricTile(),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(ZtL10n.of(context).lockNow),
              onTap: () => ref.read(vaultControllerProvider.notifier).lock(),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(ZtL10n.of(context).newRecoveryKey),
              subtitle: Text(ZtL10n.of(context).yourCurrentRecoveryKeyWillStop),
              onTap: () => _newRecoveryKey(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(ZtL10n.of(context).howYourDataIsProtected),
              subtitle: Text(ZtL10n.of(context).endToEndEncryptionInPlain),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ZtDataProtectionScreen())),
            ),
            const ZtCrashReportsTile(),
          ],
          // Crash reports do not need an account, so the row stays when
          // nobody is signed in (only in apps that set up a reporter).
          if (signedOut && ref.watch(ztCrashReporterProvider) != null) ...[
            _Header(ZtL10n.of(context).security),
            const ZtCrashReportsTile(),
          ],
          _Header(ZtL10n.of(context).appearance),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(ZtL10n.of(context).language),
            subtitle: Text(language == null
                ? ZtL10n.of(context).languagePhone
                : ZtLanguages.nativeName(language)),
            onTap: () => _pickLanguage(context, ref, language),
          ),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
            child: Column(
              children: [
                RadioListTile(
                    value: ThemeMode.system,
                    title: Text(ZtL10n.of(context).systemDefault)),
                RadioListTile(
                    value: ThemeMode.light,
                    title: Text(ZtL10n.of(context).light)),
                RadioListTile(
                    value: ThemeMode.dark,
                    title: Text(ZtL10n.of(context).dark)),
              ],
            ),
          ),
          const _DynamicColorTile(),
          if (backupSection.isNotEmpty ||
              (onDataExported != null && !signedOut)) ...[
            _Header(ZtL10n.of(context).backup),
            if (onDataExported != null && !signedOut)
              ZtExportDataTile(onExported: onDataExported!),
            ...backupSection,
          ],
          if (appSection.isNotEmpty) ...[
            _Header(config.displayName),
            ...appSection,
          ],
          _Header(ZtL10n.of(context).about),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(config.displayName),
            subtitle: Text([
              if (version != null) ZtL10n.of(context).versionLabel(version!),
              ZtL10n.of(context).endToEndEncryptedWeCant,
            ].join(' · ')),
          ),
          if (onOpenUrl != null) ...[
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(ZtL10n.of(context).helpAndFeedback),
              onTap: () => onOpenUrl!(supportUrl ?? ztSupportUrl),
            ),
            if (showSponsor && config.channel.allowsExternalPayments)
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: Text(ZtL10n.of(context).sponsorProject),
                subtitle: Text(ZtL10n.of(context).sponsorProjectSubtitle),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () => onOpenUrl!(ZtSuite.sponsorUrl),
              ),
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: Text(ZtL10n.of(context).privacyPolicy),
              onTap: () => onOpenUrl!(privacyPolicyUrl ?? ztPrivacyPolicyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(ZtL10n.of(context).termsOfUse),
              onTap: () => onOpenUrl!(termsUrl ?? ztTermsUrl),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(ZtL10n.of(context).openSourceLicences),
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
            _Header(ZtL10n.of(context).otherZeroTrustApps),
            for (final app in ZtSuite.apps)
              if (app.appId != config.appId)
                ListTile(
                  leading: ZtBrandMark(app: app, size: 40),
                  title: Text(app.fullName),
                  subtitle: Text(ZtL10n.of(context)
                      .taglineSameAccount(_tagline(context, app))),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => onOpenUrl!(app.playStoreUrl),
                ),
          ],
          if (!signedOut) ...[
            _Header(ZtL10n.of(context).dangerZone),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: theme.colorScheme.error),
              title: Text(ZtL10n.of(context).deleteAccount,
                  style: TextStyle(color: theme.colorScheme.error)),
              subtitle: Text(ZtL10n.of(context).deletesYourDataInEveryZero),
              onTap: () => _deleteAccount(context, ref),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The app's one-line description in the current language.
  static String _tagline(BuildContext context, ZtSuiteApp app) {
    final l = ZtL10n.of(context);
    return switch (app.appId) {
      'notes' => l.taglineNotes,
      'tasks' => l.taglineTasks,
      'fitness' => l.taglineFitness,
      'contacts' => l.taglineContacts,
      'clock' => l.taglineClock,
      _ => app.tagline,
    };
  }

  static String _autoLockLabel(Duration? d) {
    if (d == null) return ZtL10n.current.never;
    if (d == Duration.zero) return ZtL10n.current.immediatelyWhenYouLeaveTheApp;
    if (d.inMinutes >= 1) {
      return ZtL10n.current.autoLockAfterMinutesIdle(d.inMinutes);
    }
    return ZtL10n.current.autoLockAfterSecondsIdle(d.inSeconds);
  }

  static String _autoLockChoice(Duration? d) => switch (d) {
        null => ZtL10n.current.never,
        Duration.zero => ZtL10n.current.immediately,
        _ when d.inMinutes >= 1 => ZtL10n.current.afterMinutes(d.inMinutes),
        _ => ZtL10n.current.afterSeconds(d.inSeconds),
      };

  /// The Auto-lock picker. The timed choices and "Never" work as they
  /// always have; "Never, even after closing the app" is an extra choice
  /// that only phones with a screen lock offer (see `SessionKeyStore`).
  Future<void> _pickAutoLock(BuildContext context, WidgetRef ref,
      Duration? current, bool stayUnlocked) async {
    final account = ref.read(accountServiceProvider);
    // Browsers have their own switch for it, "Remember on this browser".
    final offerStay = !ref.read(ztCapabilitiesProvider).browserSession &&
        (SecureBiometricKeyStore.platformSupported || stayUnlocked);
    final canStay = stayUnlocked || await account.stayUnlockedAvailable();
    if (!context.mounted) return;
    final choices = {...AutoLockController.choices, current}.toList();
    // The stay-open choice is `(null, true)`; every other is `(d, false)`.
    final picked = await showDialog<(Duration?, bool)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(ZtL10n.of(context).autoLock),
        children: [
          RadioGroup<(Duration?, bool)>(
            groupValue: stayUnlocked ? (null, true) : (current, false),
            onChanged: (c) => Navigator.pop(context, c),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in choices)
                  RadioListTile<(Duration?, bool)>(
                      value: (d, false), title: Text(_autoLockChoice(d))),
                if (offerStay)
                  RadioListTile<(Duration?, bool)>(
                    value: (null, true),
                    enabled: canStay,
                    title: Text(ZtL10n.of(context).neverEvenAfterClosing),
                    subtitle: canStay
                        ? null
                        : Text(ZtL10n.of(context).needsAScreenLock),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final (after, stay) = picked;
    if (stay) {
      if (!stayUnlocked) await _turnOnStayUnlocked(context, ref);
      return;
    }
    if (stayUnlocked) {
      await ref.read(ztStayUnlockedProvider.notifier).set(false);
      await account.forgetSession();
    }
    await ref.read(ztAutoLockProvider.notifier).set(after);
  }

  /// Explains what "Never, even after closing the app" (on the web:
  /// "Remember on this browser") means, then asks for the fingerprint or
  /// password: loosening the lock is itself a sensitive action, and it
  /// yields the key to keep.
  Future<void> _turnOnStayUnlocked(BuildContext context, WidgetRef ref) async {
    final name = ref.read(ztAppConfigProvider).displayName;
    final browser = ref.read(ztCapabilitiesProvider).browserSession;
    final account = ref.read(accountServiceProvider);
    if (browser && !await account.stayUnlockedAvailable()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ZtL10n.of(context).rememberNotAvailable)));
      }
      return;
    }
    if (!context.mounted) return;
    final l = ZtL10n.of(context);
    final title = browser
        ? l.rememberOnThisBrowserQuestion(name)
        : l.keepAppOpenQuestion(name);
    final action = browser ? l.remember : l.keepOpen;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(browser
              ? l.rememberOnThisBrowserExplanation(name)
              : l.keepAppOpenExplanation(name)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ZtL10n.of(context).cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action)),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final result = await ztConfirmIdentity(
      context,
      ref,
      title: title,
      message: browser
          ? l.enterYourPasswordToRemember(name)
          : l.enterYourPasswordToKeepOpen(name),
      action: action,
    );
    if (result == null) return;
    try {
      await ref.read(ztStayUnlockedProvider.notifier).set(true);
      await ref.read(ztAutoLockProvider.notifier).set(null);
      await account.rememberSession(result.dek, legacyDek: result.legacyDek);
    } finally {
      result.dek.fillRange(0, result.dek.length, 0);
    }
  }

  /// "Remember on this browser" switched off: the kept key is removed and
  /// the app's usual auto-lock comes back, so the next visit asks for the
  /// password again.
  Future<void> _turnOffStayUnlocked(WidgetRef ref) async {
    await ref.read(ztStayUnlockedProvider.notifier).set(false);
    await ref.read(accountServiceProvider).forgetSession();
    await ref
        .read(ztAutoLockProvider.notifier)
        .set(ref.read(ztAppConfigProvider).autoLockAfter);
  }

  /// For a shared or public computer: signs out, then removes everything
  /// this site kept in the browser (the encrypted local copy, the sign-in
  /// session, a remembered key, preferences).
  Future<void> _signOutAndWipe(BuildContext context, WidgetRef ref) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ZtL10n.of(context).removeYourDataFromThisBrowser),
        content: SingleChildScrollView(
          child: Text(ZtL10n.of(context).removeFromBrowserExplanation),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ZtL10n.of(context).cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ZtL10n.of(context).signOutAndRemove)),
        ],
      ),
    );
    if (go != true) return;
    final account = ref.read(accountServiceProvider);
    final wipe = ref.read(ztBrowserWipeProvider);
    // Locking closes the local store, which the browser needs before it
    // can delete it.
    ref.read(vaultControllerProvider.notifier).lock();
    try {
      await account.signOut();
    } on Object {
      // Offline: the session is removed from this browser all the same.
    }
    await wipe();
    onSignedOut();
  }

  Future<void> _pickLanguage(
      BuildContext context, WidgetRef ref, Locale? current) async {
    const phone = 'phone';
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(ZtL10n.of(context).language),
        children: [
          RadioGroup<String>(
            groupValue: current?.languageCode ?? phone,
            onChanged: (code) => Navigator.pop(context, code),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final locale in ZtLanguages.supported)
                  RadioListTile<String>(
                    value: locale.languageCode,
                    // Each name in its own language, so it can be found
                    // whatever the app is showing now.
                    title: Text(ZtLanguages.nativeName(locale)),
                  ),
                RadioListTile<String>(
                    value: phone,
                    title: Text(ZtL10n.of(context).languagePhone)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await ref
        .read(ztLanguageProvider.notifier)
        .set(picked == phone ? null : Locale(picked));
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(ZtL10n.of(context).passwordChangedYourOtherDevicesWere)));
    }
  }

  Future<void> _newRecoveryKey(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _ConfirmPasswordDialog(
        title: ZtL10n.of(context).newRecoveryKey,
        message: ZtL10n.of(context).enterYourPasswordYourCurrentRecovery,
        action: ZtL10n.of(context).continueButton,
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
      if (kIsWeb) {
        await DatabaseAttachmentCache.deleteFor(appId: appId, userId: userId);
      } else {
        await FileAttachmentCache.deleteFor(appId: appId, userId: userId);
      }
    } on Object {
      // No platform storage (tests), or already gone.
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _ConfirmPasswordDialog(
        title: ZtL10n.of(context).deleteAccountQuestion,
        message: ZtL10n.of(context).thisPermanentlyDeletesYourAccountAnd,
        action: ZtL10n.of(context).delete,
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
      title: Text(ZtL10n.of(context).useWallpaperColours),
      subtitle: Text(ZtL10n.of(context).matchYourPhonesThemeInsteadOf),
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
      builder: (_) => _ConfirmPasswordDialog(
        title: ZtL10n.of(context).unlockWithBiometrics,
        message: ZtL10n.of(context).enterYourPasswordToTurnOn,
        action: ZtL10n.of(context).turnOn,
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
      title: Text(ZtL10n.of(context).unlockWithBiometrics),
      subtitle: Text(ZtL10n.of(context).fingerprintOrFaceOnThisDevice),
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
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(text,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary)),
      ),
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
            decoration: InputDecoration(labelText: ZtL10n.of(context).password),
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
            child: Text(ZtL10n.of(context).cancel)),
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
      title: Text(ZtL10n.of(context).changePassword),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              decoration: InputDecoration(
                  labelText: ZtL10n.of(context).currentPassword),
              obscureText: true,
            ),
            TextFormField(
              controller: _next,
              decoration:
                  InputDecoration(labelText: ZtL10n.of(context).newPassword),
              obscureText: true,
              validator: (v) => ztValidateNewPassword(v,
                  email: ref.read(accountServiceProvider).currentEmail),
            ),
            ZtPasswordStrengthMeter(
                controller: _next,
                email: ref.read(accountServiceProvider).currentEmail),
            TextFormField(
              controller: _confirm,
              decoration: InputDecoration(
                  labelText: ZtL10n.of(context).confirmNewPassword),
              obscureText: true,
              validator: (v) => v == _next.text
                  ? null
                  : ZtL10n.of(context).passwordsDontMatch,
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
            child: Text(ZtL10n.of(context).cancel)),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(ZtL10n.of(context).change)),
      ],
    );
  }
}
