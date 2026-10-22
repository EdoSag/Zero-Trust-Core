import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account/account_service.dart';
import 'account/biometric_key_store.dart';
import 'account/key_cache.dart';
import 'account/supabase_account_backend.dart';
import 'config/zt_app_config.dart';

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

/// Light / dark / system, shared by every app's Appearance setting. Apps
/// persist it however they persist other preferences.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
