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

  /// Cancels a scheduled deletion. False when none was scheduled.
  Future<bool> keepAccount();
}
