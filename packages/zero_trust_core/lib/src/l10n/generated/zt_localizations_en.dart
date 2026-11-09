// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'zt_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ZtLocalizationsEn extends ZtLocalizations {
  ZtLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get unlockWithBiometricsQuestion => 'Unlock with biometrics?';

  @override
  String get useYourFingerprintOrFaceTo =>
      'Use your fingerprint or face to open the app on this phone. You can change this in Settings.';

  @override
  String get notNow => 'Not now';

  @override
  String get turnOn => 'Turn on';

  @override
  String get sentAgainCheckYourInboxAnd =>
      'Sent again. Check your inbox and spam folder.';

  @override
  String get signUpIntro =>
      'One account for every Zero-Trust app. Your password never leaves this device.';

  @override
  String get signInWithYourZeroTrust => 'Sign in with your Zero-Trust account.';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get enterYourPassword => 'Enter your password.';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordsDontMatch => 'Passwords don\'t match.';

  @override
  String get resendConfirmationEmail => 'Resend confirmation email';

  @override
  String get creatingAccount => 'Creating account';

  @override
  String get signingIn => 'Signing in';

  @override
  String get createAccount => 'Create account';

  @override
  String get signIn => 'Sign in';

  @override
  String get iAlreadyHaveAnAccount => 'I already have an account';

  @override
  String get createAZeroTrustAccount => 'Create a Zero-Trust account';

  @override
  String get forgotPasswordQuestion => 'Forgot password?';

  @override
  String get unlock => 'Unlock';

  @override
  String get unlockWithBiometrics => 'Unlock with biometrics';

  @override
  String get signOut => 'Sign out';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get yourDataIsEncryptedWithYour =>
      'Your data is encrypted with your password, so resetting it needs two things: a link we email you, and the recovery key you saved when you created your account.';

  @override
  String get emailMeAResetLink => 'Email me a reset link';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get enterTheRecoveryKeyYouSaved =>
      'Enter the recovery key you saved when you created your account, then choose a new password.';

  @override
  String get recoveryKey => 'Recovery key';

  @override
  String get enterYourRecoveryKey => 'Enter your recovery key.';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get saveYourRecoveryKey => 'Save your recovery key';

  @override
  String get thisKeyIsTheOnlyWay =>
      'This key is the only way back into your data if you forget your password. We can\'t reset it for you, because we never see your password or your data.';

  @override
  String get copy => 'Copy';

  @override
  String get copiedStoreItSomewhereSafeAnd =>
      'Copied. Store it somewhere safe and offline.';

  @override
  String get iSavedMyRecoveryKeySomewhere =>
      'I saved my recovery key somewhere safe';

  @override
  String get continueButton => 'Continue';

  @override
  String get onlyYouCanReadYourData => 'Only you can read your data';

  @override
  String get everythingIsEncryptedOnThisPhone =>
      'Everything is encrypted on this phone before it\'s saved or synced. We never see your password, so we can\'t read your data, and neither can anyone who breaks into our servers.';

  @override
  String get keepYourRecoveryKeySafe => 'Keep your recovery key safe';

  @override
  String get whenYouCreateYourAccountYou =>
      'When you create your account you get a recovery key. It\'s the only way back in if you forget your password, because we can\'t reset it for you. Write it down or keep it in a password manager.';

  @override
  String get unlockWithATouch => 'Unlock with a touch';

  @override
  String get turnOnFingerprintOrFaceUnlock =>
      'Turn on fingerprint or face unlock after you sign in. It stays on this phone, and your password still works everywhere. One account opens every Zero-Trust app.';

  @override
  String get skip => 'Skip';

  @override
  String get getStarted => 'Get started';

  @override
  String get next => 'Next';

  @override
  String get encryptedOnYourPhone => 'Encrypted on your phone';

  @override
  String get everythingYouWriteIsEncryptedOn =>
      'Everything you write is encrypted on this device before it goes anywhere, with AES-256, the standard banks and governments use. Our servers only ever store scrambled data they can\'t read.';

  @override
  String get onlyYourPasswordCanUnlockIt => 'Only your password can unlock it';

  @override
  String get yourEncryptionKeyIsMadeFrom =>
      'Your encryption key is made from your password on your phone. The password itself never leaves the device: we receive a separate value derived from it, which can sign you in but can\'t decrypt anything. Not us, not our hosting provider, and not anyone who breaks into our servers can read your data. (An account made with an older app version sends its password once more, the first time it signs in after updating, to switch over to this.)';

  @override
  String get yourRecoveryKeyIsTheOnly => 'Your recovery key is the only backup';

  @override
  String get becauseWeCantReadYourData =>
      'Because we can\'t read your data, we can\'t reset your password for you either. Your recovery key is the one way back in if you forget your password. Keep it somewhere safe, offline. You can make a new one in Settings at any time.';

  @override
  String get protectedOnTheDeviceToo => 'Protected on the device too';

  @override
  String get theCopyKeptOnYourPhone =>
      'The copy kept on your phone is encrypted as well, and locks after the time you choose under Auto-lock. Fingerprint or face unlock keeps your key in the phone\'s secure hardware.';

  @override
  String get tamperProofSync => 'Tamper-proof sync';

  @override
  String get eachItemIsSignedWithA =>
      'Each item is signed with a key only your devices have, so a changed or swapped item on the server is spotted and refused rather than shown to you.';

  @override
  String get oneAccountSeparateKeys => 'One account, separate keys';

  @override
  String get theSameAccountWorksInEvery =>
      'The same account works in every Zero-Trust app, but each app encrypts with its own key, derived from yours.';

  @override
  String get whatWeCanSee => 'What we can see';

  @override
  String get yourEmailAddressWhenYouSign =>
      'Your email address, when you sign in, how many items you store and their size, and when they change. Never what they say.';

  @override
  String get breachedPasswordCheck => 'Breached-password check';

  @override
  String get whenYouChooseANewPassword =>
      'When you choose a new password, we check it against known data breaches without sending it: only the first 5 characters of a one-way fingerprint go to Have I Been Pwned, and the match is done on your phone.';

  @override
  String get deleteEverythingAnyTime => 'Delete everything, any time';

  @override
  String get deletingYourAccountUnderSettingsDanger =>
      'Deleting your account under Settings → Danger zone removes your data from our servers in every Zero-Trust app.';

  @override
  String get howYourDataIsProtected => 'How your data is protected';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get notSignedIn => 'Not signed in';

  @override
  String get oneAccountForEveryApp => 'One account for every Zero-Trust app';

  @override
  String get changePassword => 'Change password';

  @override
  String get security => 'Security';

  @override
  String get autoLock => 'Auto-lock';

  @override
  String get lockNow => 'Lock now';

  @override
  String get newRecoveryKey => 'New recovery key';

  @override
  String get yourCurrentRecoveryKeyWillStop =>
      'Your current recovery key will stop working';

  @override
  String get endToEndEncryptionInPlain =>
      'End-to-end encryption, in plain words';

  @override
  String get appearance => 'Appearance';

  @override
  String get systemDefault => 'System default';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get backup => 'Backup';

  @override
  String get about => 'About';

  @override
  String get endToEndEncryptedWeCant =>
      'End-to-end encrypted. We can\'t read your data.';

  @override
  String get helpAndFeedback => 'Help and feedback';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfUse => 'Terms of use';

  @override
  String get openSourceLicences => 'Open-source licences';

  @override
  String get otherZeroTrustApps => 'Other Zero-Trust apps';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deletesYourDataInEveryZero =>
      'Deletes your data in every Zero-Trust app';

  @override
  String get never => 'Never';

  @override
  String get immediatelyWhenYouLeaveTheApp =>
      'Immediately when you leave the app';

  @override
  String get immediately => 'Immediately';

  @override
  String get passwordChangedYourOtherDevicesWere =>
      'Password changed. Your other devices were signed out.';

  @override
  String get enterYourPasswordYourCurrentRecovery =>
      'Enter your password. Your current recovery key will stop working.';

  @override
  String get deleteAccountQuestion => 'Delete account?';

  @override
  String get thisPermanentlyDeletesYourAccountAnd =>
      'This permanently deletes your account and your data in every Zero-Trust app. It can\'t be undone.';

  @override
  String get delete => 'Delete';

  @override
  String get useWallpaperColours => 'Use wallpaper colours';

  @override
  String get matchYourPhonesThemeInsteadOf =>
      'Match your phone\'s theme instead of the app\'s';

  @override
  String get enterYourPasswordToTurnOn =>
      'Enter your password to turn on fingerprint or face unlock on this device.';

  @override
  String get fingerprintOrFaceOnThisDevice =>
      'Fingerprint or face, on this device only';

  @override
  String get cancel => 'Cancel';

  @override
  String get currentPassword => 'Current password';

  @override
  String get change => 'Change';

  @override
  String get syncing => 'Syncing…';

  @override
  String get notSyncedYet => 'Not synced yet';

  @override
  String get syncedJustNow => 'Synced just now';

  @override
  String get exportMyDataQuestion => 'Export my data?';

  @override
  String get youGetOneZipFileWith =>
      'You get one ZIP file with everything in this app, readable by any computer. It isn\'t encrypted, so anyone who gets the file can read it. Keep it somewhere safe.';

  @override
  String get export => 'Export';

  @override
  String get exportMyData => 'Export my data';

  @override
  String get aZipOfEverythingInThis =>
      'A ZIP of everything in this app, not encrypted';

  @override
  String get exporting => 'Exporting';

  @override
  String pageOf(int page, int count) {
    return 'Page $page of $count';
  }

  @override
  String appIsLocked(String appName) {
    return '$appName is locked';
  }

  @override
  String get unlocking => 'Unlocking';

  @override
  String checkEmailForResetLink(String email) {
    return 'Check $email for a reset link. Open it on this device, then enter your recovery key.';
  }

  @override
  String recoveryKeySpelled(String spelled) {
    return 'Recovery key: $spelled';
  }

  @override
  String zeroTrustMeans(String appName) {
    return 'Zero-trust means you don\'t have to trust us with your data. Here\'s how $appName keeps it private.';
  }

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String taglineSameAccount(String tagline) {
    return '$tagline · same account';
  }

  @override
  String autoLockAfterMinutesIdle(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'After $minutes min in the background or idle',
      one: 'After 1 min in the background or idle',
    );
    return '$_temp0';
  }

  @override
  String autoLockAfterSecondsIdle(int seconds) {
    return 'After $seconds s in the background or idle';
  }

  @override
  String afterMinutes(int minutes) {
    return 'After $minutes min';
  }

  @override
  String afterSeconds(int seconds) {
    return 'After $seconds s';
  }

  @override
  String syncedMinutesAgo(int minutes) {
    return 'Synced $minutes min ago';
  }

  @override
  String syncedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Synced $hours hours ago',
      one: 'Synced 1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String syncedDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Synced $days days ago',
      one: 'Synced yesterday',
    );
    return '$_temp0';
  }

  @override
  String attachmentsNotIncluded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count attached files couldn\'t be included. Try again when online.',
      one: '1 attached file couldn\'t be included. Try again when online.',
    );
    return '$_temp0';
  }

  @override
  String get strengthVeryWeak => 'Very weak';

  @override
  String get strengthWeak => 'Weak';

  @override
  String get strengthFair => 'Fair';

  @override
  String get strengthGood => 'Good';

  @override
  String get strengthStrong => 'Strong';

  @override
  String get enterAPassword => 'Enter a password.';

  @override
  String get tipNoEmail => 'Don\'t use your email in it.';

  @override
  String get tipCommonWords => 'Avoid common words and passwords.';

  @override
  String get tipRepeated => 'Avoid repeated characters like \"aaa\".';

  @override
  String get tipSequences => 'Avoid sequences like \"1234\" or \"qwerty\".';

  @override
  String get tipYears => 'Avoid years and dates.';

  @override
  String get tipLonger => 'Make it longer: a few unrelated words work well.';

  @override
  String get tipMix => 'Mix in words, numbers or symbols.';

  @override
  String get passwordBreached =>
      'This password has appeared in data breaches, so attackers try it first. Choose a different one.';

  @override
  String get errOffline =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get errInvalidCredentials => 'That email and password don\'t match.';

  @override
  String get errEmailNotConfirmed =>
      'Confirm your email first: open the link we sent you.';

  @override
  String get errKeyMismatch =>
      'This password can\'t unlock your data. Use your recovery key to reset it.';

  @override
  String get errBiometricChanged =>
      'Your fingerprints or face changed, so biometric unlock was turned off. Unlock with your password, then turn it back on in Settings.';

  @override
  String get errRecoveryKeyInvalid =>
      'That recovery key isn\'t valid. Check it for typos.';

  @override
  String get errSessionEnded => 'Your session ended. Sign in again.';

  @override
  String get errFileTooLargeUpload => 'That file is too large to upload.';

  @override
  String get errAttachmentNotFound =>
      'This file isn\'t available yet. It will appear once the device that added it is back online.';

  @override
  String get errAttachmentCorrupt =>
      'This file was damaged or changed on the server, so it wasn\'t opened.';

  @override
  String get errNewerVersion =>
      'This was changed in a newer version of the app. Update the app to edit it.';

  @override
  String get errLocalStoreUnreadable =>
      'Data on this device couldn\'t be opened. It will be downloaded again.';

  @override
  String get errVaultLocked => 'Unlock the app first.';

  @override
  String get errTooMany =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get errServerDown =>
      'Our server isn\'t responding right now. Your data is safe; try again soon.';

  @override
  String get errGeneric =>
      'Something went wrong. Check your connection and try again.';

  @override
  String get enterValidEmail => 'Enter a valid email address.';

  @override
  String get useAtLeast12 => 'Use at least 12 characters.';

  @override
  String get tipDefaultLonger => 'Make it longer.';

  @override
  String get syncFailedRetry => 'Couldn\'t sync. Tap to retry';

  @override
  String errConfirmationSent(String email) {
    return 'We sent a confirmation link to $email. Open it, then sign in.';
  }

  @override
  String errFileTooLarge(int megabytes) {
    return 'That file is too large. The limit is $megabytes MB.';
  }

  @override
  String tooEasyToGuess(String hint) {
    return 'Too easy to guess. $hint';
  }

  @override
  String itemsUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items couldn\'t be read',
      one: '1 item couldn\'t be read',
    );
    return '$_temp0';
  }
}
