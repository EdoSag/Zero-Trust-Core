import 'package:flutter/material.dart';

import '../../l10n/zt_l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../config/zt_suite.dart';
import '../brand/zt_brand_mark.dart';
import '../theme/zt_theme.dart';

/// "How your data is protected": the plain-language version of the core's
/// security design, the same in every app. Opened from Settings → Security
/// and usable in onboarding.
///
/// Every sentence here must stay true of the code. When the design changes
/// (README "Key hierarchy"), update this screen in the same change.
class ZtDataProtectionScreen extends ConsumerWidget {
  const ZtDataProtectionScreen({super.key});

  /// The sections in the current language.
  static List<(IconData, String, String)> get sections =>
      sectionsFor(ZtL10n.current);

  static List<(IconData, String, String)> sectionsFor(ZtLocalizations l) => [
        (
          Icons.lock_outline,
          l.encryptedOnYourPhone,
          l.everythingYouWriteIsEncryptedOn,
        ),
        (
          Icons.key_outlined,
          l.onlyYourPasswordCanUnlockIt,
          l.yourEncryptionKeyIsMadeFrom,
        ),
        (
          Icons.health_and_safety_outlined,
          l.yourRecoveryKeyIsTheOnly,
          l.becauseWeCantReadYourData,
        ),
        (
          Icons.phone_android_outlined,
          l.protectedOnTheDeviceToo,
          l.theCopyKeptOnYourPhone,
        ),
        (
          Icons.verified_user_outlined,
          l.tamperProofSync,
          l.eachItemIsSignedWithA,
        ),
        (
          Icons.apps_outlined,
          l.oneAccountSeparateKeys,
          l.theSameAccountWorksInEvery,
        ),
        (
          Icons.visibility_off_outlined,
          l.whatWeCanSee,
          l.yourEmailAddressWhenYouSign,
        ),
        (
          Icons.password,
          l.breachedPasswordCheck,
          l.whenYouChooseANewPassword,
        ),
        (
          Icons.delete_outline,
          l.deleteEverythingAnyTime,
          l.deletingYourAccountUnderSettingsDanger,
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ztAppConfigProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(ZtL10n.of(context).howYourDataIsProtected)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            ZtSpacing.lg, ZtSpacing.sm, ZtSpacing.lg, ZtSpacing.xl),
        children: [
          Center(child: ZtBrandMark(app: ZtSuite.byId(config.appId))),
          const SizedBox(height: ZtSpacing.md),
          Text(
            ZtL10n.of(context).zeroTrustMeans(config.displayName),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: ZtSpacing.lg),
          for (final (icon, title, body) in sectionsFor(ZtL10n.of(context)))
            Padding(
              padding: const EdgeInsets.only(bottom: ZtSpacing.lg),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: ZtSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: ZtSpacing.xs),
                          Text(body, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
