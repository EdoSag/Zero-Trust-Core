import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account/account_service.dart';
import 'account/biometric_key_store.dart';
import 'account/key_cache.dart';
import 'account/supabase_account_backend.dart';
import 'config/zt_app_config.dart';
import 'config/zt_preferences.dart';

/// The account service every shared screen uses. Tests override it with a
/// fake backend.
final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    SupabaseAccountBackend(),
    keyCache: SecureStorageKeyCache(),
    biometrics: SecureBiometricKeyStore(
      promptTitle: 'Unlock ${ref.watch(ztAppConfigProvider).displayName}',
    ),
  ),
);

/// Light / dark / system, shared by every app's Appearance setting and
/// remembered per install.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  bool _chosen = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final String? stored;
    try {
      stored = await ref.read(ztPreferencesStoreProvider).read(_key);
    } on Object {
      return;
    }
    if (_chosen) return;
    for (final m in ThemeMode.values) {
      if (m.name == stored) state = m;
    }
  }

  Future<void> set(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    try {
      await ref.read(ztPreferencesStoreProvider).write(_key, mode.name);
    } on Object {
      // Not remembered; it still applies for this session.
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Whether to use the wallpaper's colours (Material You, Android 12+)
/// instead of the suite's brand colours. Off by default, remembered per
/// install.
class DynamicColorController extends Notifier<bool> {
  static const _key = 'dynamic_color';
  bool _chosen = false;

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final stored = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (!_chosen && stored != null) state = stored == 'true';
    } on Object {
      // Keep the default.
    }
  }

  Future<void> set(bool on) async {
    _chosen = true;
    state = on;
    try {
      await ref.read(ztPreferencesStoreProvider).write(_key, '$on');
    } on Object {
      // Applies for this session only.
    }
  }
}

final ztDynamicColorProvider =
    NotifierProvider<DynamicColorController, bool>(DynamicColorController.new);
