/// Optional account features on top of [AccountBackend]. A backend that
/// doesn't implement this (an app's test fake, for example) simply doesn't
/// offer them, so adding features here never breaks an app's tests.
///
/// The Supabase backend implements it.
abstract interface class AccountLifecycleBackend {
  /// Asks the server to delete the account after the grace period (Z22) and
  /// signs out. Returns when it will be deleted. The server refuses unless
  /// this session signed in within the last few minutes.
  Future<DateTime> requestDeletion();

  /// When the signed-in account is set to be deleted, or null.
  Future<DateTime?> pendingDeletion();

  /// Cancels a scheduled deletion. False when none was scheduled, or when
  /// the deletion has already started ([pendingDeletion] still has a date).
  Future<bool> keepAccount();

  /// Emails a 6-digit code to [newEmail] (Z14). Throws [EmailInUse] when the
  /// address already has an account. Needs a fresh password sign-in.
  Future<void> startEmailChange(String newEmail);

  /// With the emailed [code], switches the account's email and its sign-in
  /// secret ([authSecret], derived from the password and the new email) in
  /// one server step, then refreshes the session. Returns the new email.
  /// Throws [EmailChangeCodeWrong] or [EmailChangeExpired].
  Future<String> finishEmailChange(String code, String authSecret);
}

/// The new address already belongs to an account.
class EmailInUse implements Exception {
  const EmailInUse();
  @override
  String toString() => 'EmailInUse';
}

/// The email-change code doesn't match (a few tries are allowed).
class EmailChangeCodeWrong implements Exception {
  const EmailChangeCodeWrong();
  @override
  String toString() => 'EmailChangeCodeWrong';
}

/// The email-change code expired or was tried too often: ask for a new one.
class EmailChangeExpired implements Exception {
  const EmailChangeExpired();
  @override
  String toString() => 'EmailChangeExpired';
}
