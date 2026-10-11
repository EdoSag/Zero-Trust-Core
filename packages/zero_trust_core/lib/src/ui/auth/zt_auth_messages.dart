import '../../account/account_backend.dart';
import '../../account/account_service.dart';

/// Turns account errors into one plain sentence for the user.
String ztAuthErrorMessage(Object error) => switch (error) {
      InvalidCredentials() => 'That email and password don\'t match.',
      KeyMismatch() =>
        'This password can\'t unlock your data. Use your recovery key to reset it.',
      ArgumentError(:final message) => '$message',
      FormatException() =>
        'That recovery key isn\'t valid. Check it for typos.',
      _ => 'Something went wrong. Check your connection and try again.',
    };

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
