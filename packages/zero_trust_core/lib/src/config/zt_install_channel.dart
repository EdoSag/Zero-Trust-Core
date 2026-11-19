import 'package:flutter/foundation.dart';

/// Where this build of the app is distributed. Decides which payment and
/// donation options the app may show: store rules forbid pointing people to
/// other ways to pay from inside a store build.
///
/// Set at build time with `--dart-define=ZT_CHANNEL=direct|play|appStore`.
/// Without it, Android and web builds count as [play] and Apple builds as
/// [appStore], so a build that forgets the flag never shows outside
/// payment links.
enum ZtInstallChannel {
  /// APK from GitHub releases or the website. Outside links are allowed.
  direct,

  /// Google Play. Only Google Play Billing; no outside payment links.
  play,

  /// Apple App Store. Only Apple in-app purchase; no outside payment links.
  appStore;

  /// May the app link to donations or a web checkout?
  bool get allowsExternalPayments => this == direct;

  static ZtInstallChannel fromName(String? name, {TargetPlatform? platform}) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    final p = platform ?? defaultTargetPlatform;
    return p == TargetPlatform.iOS || p == TargetPlatform.macOS
        ? appStore
        : play;
  }

  /// This build's channel, from `ZT_CHANNEL`.
  static final ZtInstallChannel current = fromName(
    const bool.hasEnvironment('ZT_CHANNEL')
        ? const String.fromEnvironment('ZT_CHANNEL')
        : null,
  );
}
