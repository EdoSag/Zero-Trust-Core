import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account/account_service.dart';
import 'account/supabase_account_backend.dart';

/// The account service every shared screen uses. Tests override it with a
/// fake backend.
final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(SupabaseAccountBackend()),
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
