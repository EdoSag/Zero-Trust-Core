import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'zt_install_channel.dart';

/// What makes one Zero-Trust app different from its siblings. Everything
/// else (account, lock, settings layout, theme) comes from the core.
class ZtAppConfig {
  const ZtAppConfig({
    required this.appId,
    required this.displayName,
    this.accent,
    this.autoLockAfter = const Duration(minutes: 5),
    ZtInstallChannel? channel,
    String? releaseRepo,
  })  : _channel = channel,
        _releaseRepo = releaseRepo;

  /// Lowercase id, also the HKDF label and the `vault_items.app` value:
  /// `fitness`, `contacts`, `tasks`, `notes`.
  final String appId;

  /// Store name, for example "Zero-Trust Notes".
  final String displayName;

  /// Optional per-app accent. The brand seed stays shared.
  final Color? accent;

  /// `null` disables auto-lock.
  final Duration? autoLockAfter;

  final ZtInstallChannel? _channel;

  /// Where this build is distributed. Defaults to
  /// [ZtInstallChannel.current] (the `ZT_CHANNEL` build flag); tests and
  /// previews may pass one.
  ZtInstallChannel get channel => _channel ?? ZtInstallChannel.current;

  final String? _releaseRepo;

  /// The GitHub repository whose releases carry this app's signed APK
  /// (`owner/name`), for the in-app update check and Obtainium. Defaults
  /// to the suite's naming: "Zero-Trust Notes" -> `EdoSag/Zero-Trust-Notes`.
  String get releaseRepo =>
      _releaseRepo ?? 'EdoSag/${displayName.trim().replaceAll(' ', '-')}';
}

/// Apps override this in their root `ProviderScope`.
final ztAppConfigProvider = Provider<ZtAppConfig>(
  (ref) =>
      throw UnimplementedError('Override ztAppConfigProvider in ProviderScope'),
);
