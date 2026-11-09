import 'package:flutter/material.dart';
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

  static const sections = <(IconData, String, String)>[
    (
      Icons.lock_outline,
      'Encrypted on your phone',
      'Everything you write is encrypted on this device before it goes '
          'anywhere, with AES-256, the standard banks and governments use. '
          'Our servers only ever store scrambled data they can\'t read.',
    ),
    (
      Icons.key_outlined,
      'Only your password can unlock it',
      'Your encryption key is made from your password on your phone. The '
          'password itself never leaves the device: we receive a separate '
          'value derived from it, which can sign you in but can\'t decrypt '
          'anything. Not us, not our hosting provider, and not anyone who '
          'breaks into our servers can read your data. (An account made with '
          'an older app version sends its password once more, the first time '
          'it signs in after updating, to switch over to this.)',
    ),
    (
      Icons.health_and_safety_outlined,
      'Your recovery key is the only backup',
      'Because we can\'t read your data, we can\'t reset your password for '
          'you either. Your recovery key is the one way back in if you forget '
          'your password. Keep it somewhere safe, offline. You can make a new '
          'one in Settings at any time.',
    ),
    (
      Icons.phone_android_outlined,
      'Protected on the device too',
      'The copy kept on your phone is encrypted as well, and locks after the '
          'time you choose under Auto-lock. Fingerprint or face unlock keeps '
          'your key in the phone\'s secure hardware.',
    ),
    (
      Icons.verified_user_outlined,
      'Tamper-proof sync',
      'Each item is signed with a key only your devices have, so a changed '
          'or swapped item on the server is spotted and refused rather than '
          'shown to you.',
    ),
    (
      Icons.apps_outlined,
      'One account, separate keys',
      'The same account works in every Zero-Trust app, but each app '
          'encrypts with its own key, derived from yours.',
    ),
    (
      Icons.visibility_off_outlined,
      'What we can see',
      'Your email address, when you sign in, how many items you store and '
          'their size, and when they change. Never what they say.',
    ),
    (
      Icons.password,
      'Breached-password check',
      'When you choose a new password, we check it against known data '
          'breaches without sending it: only the first 5 characters of a '
          'one-way fingerprint go to Have I Been Pwned, and the match is done '
          'on your phone.',
    ),
    (
      Icons.delete_outline,
      'Delete everything, any time',
      'Deleting your account under Settings → Danger zone removes your data '
          'from our servers in every Zero-Trust app.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(ztAppConfigProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('How your data is protected')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            ZtSpacing.lg, ZtSpacing.sm, ZtSpacing.lg, ZtSpacing.xl),
        children: [
          Center(child: ZtBrandMark(app: ZtSuite.byId(config.appId))),
          const SizedBox(height: ZtSpacing.md),
          Text(
            'Zero-trust means you don\'t have to trust us with your data. '
            'Here\'s how ${config.displayName} keeps it private.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: ZtSpacing.lg),
          for (final (icon, title, body) in sections)
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
