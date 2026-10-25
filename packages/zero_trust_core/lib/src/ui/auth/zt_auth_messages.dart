import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../account/account_backend.dart';
import '../../account/account_service.dart';
import '../../account/biometric_key_store.dart';

const _offline = 'You\'re offline. Check your connection and try again.';

/// Turns account errors into one plain sentence for the user.
String ztAuthErrorMessage(Object error) => switch (error) {
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
