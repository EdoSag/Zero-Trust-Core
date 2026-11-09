import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;
import 'package:zt_crypto/zt_crypto.dart' show AttachmentCorrupt;

import '../../account/account_backend.dart';
import '../../account/account_service.dart';
import '../../account/biometric_key_store.dart';
import '../../account/password_check.dart';
import '../../attachments/attachment_backend.dart';
import '../../attachments/zt_attachments.dart';
import '../../sync/sync_providers.dart';
import '../../sync/zt_collection.dart';
import '../../sync/zt_local_store.dart';

const _offline = 'You\'re offline. Check your connection and try again.';

/// Turns account errors into one plain sentence for the user. Same as
/// [ztErrorMessage], which covers sync and attachment errors too.
String ztAuthErrorMessage(Object error) => ztErrorMessage(error);

/// Turns any error the core raises into one plain sentence for the user,
/// telling apart what the user can fix (offline, wait, sign in again,
/// update the app) from what they can't (server down: data is safe).
String ztErrorMessage(Object error) => switch (error) {
      InvalidCredentials() => 'That email and password don\'t match.',
      EmailNotConfirmed() =>
        'Confirm your email first: open the link we sent you.',
      EmailConfirmationSent(:final email) =>
        'We sent a confirmation link to $email. Open it, then sign in.',
      KeyMismatch() =>
        'This password can\'t unlock your data. Use your recovery key to reset it.',
      BiometricKeyInvalidated() =>
        'Your fingerprints or face changed, so biometric unlock was turned off. '
            'Unlock with your password, then turn it back on in Settings.',
      ArgumentError(:final message) => '$message',
      StateError(:final message) => message,
      FormatException() =>
        'That recovery key isn\'t valid. Check it for typos.',
      TimeoutException() => _offline,
      AuthException(:final statusCode, :final code) => switch (statusCode) {
          null => _offline, // no response at all
          '429' => _tooMany,
          _
              when code == 'over_request_rate_limit' ||
                  code == 'over_email_send_rate_limit' =>
            _tooMany,
          '401' || '403' => 'Your session ended. Sign in again.',
          _ when (int.tryParse(statusCode) ?? 0) >= 500 => _serverDown,
          _ => _generic,
        },
      PostgrestException(:final code) => switch (code) {
          '42501' ||
          'PGRST301' ||
          'PGRST303' =>
            'Your session ended. Sign in again.',
          '429' => _tooMany,
          _ when (code ?? '').startsWith('5') => _serverDown,
          _ when _looksOffline(error) => _offline,
          _ => _serverDown,
        },
      StorageException(:final statusCode) => switch (statusCode) {
          null => _offline,
          '413' => 'That file is too large to upload.',
          '429' => _tooMany,
          '401' || '403' => 'Your session ended. Sign in again.',
          _ when (int.tryParse(statusCode) ?? 0) >= 500 => _serverDown,
          _ => _generic,
        },
      AttachmentTooLarge(:final limit) =>
        'That file is too large. The limit is ${limit ~/ 1000000} MB.',
      AttachmentNotFound() =>
        'This file isn\'t available yet. It will appear once the device that '
            'added it is back online.',
      AttachmentCorrupt() =>
        'This file was damaged or changed on the server, so it wasn\'t opened.',
      ItemFromNewerVersion() =>
        'This was changed in a newer version of the app. Update the app to edit it.',
      LocalStoreUnreadable() =>
        'Data on this device couldn\'t be opened. It will be downloaded again.',
      VaultIsLocked() => 'Unlock the app first.',
      _ when _looksOffline(error) => _offline,
      _ => _generic,
    };

const _tooMany = 'Too many attempts. Wait a few minutes and try again.';
const _serverDown =
    'Our server isn\'t responding right now. Your data is safe; try again soon.';
const _generic = 'Something went wrong. Check your connection and try again.';

/// Network failures arrive as `SocketException` or `ClientException`,
/// which the core can't import on every platform, so match the name.
bool _looksOffline(Object error) {
  final s = error.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection refused');
}

String? ztValidateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? ztValidatePassword(String? value) {
  if ((value ?? '').length < 12) return 'Use at least 12 characters.';
  return null;
}

/// For a password being chosen (sign-up, change, reset): at least 12
/// characters and rated "Good" or better by [estimatePasswordStrength].
/// Never used when signing in, so older accounts with weaker passwords
/// still get in.
String? ztValidateNewPassword(String? value, {String? email}) {
  final short = ztValidatePassword(value);
  if (short != null) return short;
  final strength = estimatePasswordStrength(value!, email: email);
  if (!strength.acceptable) {
    return 'Too easy to guess. ${strength.hint ?? 'Make it longer.'}';
  }
  return null;
}
