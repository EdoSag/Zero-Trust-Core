import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What makes one Zero-Trust app different from its siblings. Everything
/// else (account, lock, settings layout, theme) comes from the core.
class ZtAppConfig {
  const ZtAppConfig({
    required this.appId,
    required this.displayName,
    this.accent,
    this.autoLockAfter = const Duration(minutes: 5),
  });

  /// Lowercase id, also the HKDF label and the `vault_items.app` value:
  /// `fitness`, `contacts`, `tasks`, `notes`.
  final String appId;

  /// Store name, for example "Zero-Trust Notes".
  final String displayName;

  /// Optional per-app accent. The brand seed stays shared.
  final Color? accent;

  /// `null` disables auto-lock.
  final Duration? autoLockAfter;
}

/// Apps override this in their root `ProviderScope`.
final ztAppConfigProvider = Provider<ZtAppConfig>(
  (ref) =>
      throw UnimplementedError('Override ztAppConfigProvider in ProviderScope'),
);
