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
import '../../platform/zt_database.dart';
import '../../sync/sync_providers.dart';
import '../../sync/zt_collection.dart';
import '../../sync/zt_local_store.dart';
import '../../l10n/zt_l10n.dart';

/// Turns account errors into one plain sentence for the user. Same as
/// [ztErrorMessage], which covers sync and attachment errors too.
String ztAuthErrorMessage(Object error) => ztErrorMessage(error);

/// Turns any error the core raises into one plain sentence for the user,
/// telling apart what the user can fix (offline, wait, sign in again,
/// update the app) from what they can't (server down: data is safe).
String ztErrorMessage(Object error) {
  final l = ZtL10n.current;
  return switch (error) {
    InvalidCredentials() => l.errInvalidCredentials,
    EmailNotConfirmed() => l.errEmailNotConfirmed,
    EmailConfirmationSent(:final email) => l.errConfirmationSent(email),
    KeyMismatch() => l.errKeyMismatch,
    BiometricKeyInvalidated() => l.errBiometricChanged,
    ArgumentError(:final message) => '$message',
    StateError(:final message) => message,
    FormatException() => l.errRecoveryKeyInvalid,
    TimeoutException() => l.errOffline,
    AuthException(:final statusCode, :final code) => switch (statusCode) {
        null => l.errOffline, // no response at all
        '429' => l.errTooMany,
        _
            when code == 'over_request_rate_limit' ||
                code == 'over_email_send_rate_limit' =>
          l.errTooMany,
        '401' || '403' => l.errSessionEnded,
        _ when (int.tryParse(statusCode) ?? 0) >= 500 => l.errServerDown,
        _ => l.errGeneric,
      },
    PostgrestException(:final code) => switch (code) {
        '42501' || 'PGRST301' || 'PGRST303' => l.errSessionEnded,
        '429' => l.errTooMany,
        _ when (code ?? '').startsWith('5') => l.errServerDown,
        _ when _looksOffline(error) => l.errOffline,
        _ => l.errServerDown,
      },
    StorageException(:final statusCode) => switch (statusCode) {
        null => l.errOffline,
        '413' => l.errFileTooLargeUpload,
        '429' => l.errTooMany,
        '401' || '403' => l.errSessionEnded,
        _ when (int.tryParse(statusCode) ?? 0) >= 500 => l.errServerDown,
        _ => l.errGeneric,
      },
    AttachmentTooLarge(:final limit) => l.errFileTooLarge(limit ~/ 1000000),
    AttachmentNotFound() => l.errAttachmentNotFound,
    AttachmentCorrupt() => l.errAttachmentCorrupt,
    ItemFromNewerVersion() => l.errNewerVersion,
    LocalStoreUnreadable() => l.errLocalStoreUnreadable,
    LocalStoreInUse() => l.errStoreInUse,
    VaultIsLocked() => l.errVaultLocked,
    _ when _looksOffline(error) => l.errOffline,
    _ => l.errGeneric,
  };
}

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
    return ZtL10n.current.enterValidEmail;
  }
  return null;
}

String? ztValidatePassword(String? value) {
  if ((value ?? '').length < 12) return ZtL10n.current.useAtLeast12;
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
    return ZtL10n.current
        .tooEasyToGuess(strength.hint ?? ZtL10n.current.tipDefaultLonger);
  }
  return null;
}
