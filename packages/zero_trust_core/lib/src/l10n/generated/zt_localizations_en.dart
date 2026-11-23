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
  String get signInOrCreateAccount => 'Sign in or create an account';

  @override
  String get signInToBackUpAndSync =>
      'Back up and sync with your Zero-Trust account';

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
  String get sponsorProject => 'Support the project';

  @override
  String get sponsorProjectSubtitle =>
      'Sponsor development on GitHub. It\'s a thank-you and doesn\'t unlock anything.';

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
      'Your account and your data in every Zero-Trust app will be deleted for good after 7 days. Until then you can change your mind.';

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
  String get errStoreInUse =>
      'This app is already open in another tab or window. Close it there, then reload this page.';

  @override
  String get errVaultLocked => 'Unlock the app first.';

  @override
  String get errTooMany =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get errServerDown =>
      'Our server isn\'t responding right now. Your data is safe; try again soon.';

  @override
  String get errEmailNotSent =>
      'We couldn\'t send the email. The problem is on our side, not yours. Try again later.';

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

  @override
  String get storageFull =>
      'Storage full. New changes stay on this device until you delete something';

  @override
  String itemsTooLarge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are too large to sync',
      one: '1 item is too large to sync',
    );
    return '$_temp0';
  }

  @override
  String get storage => 'Storage';

  @override
  String storageUsed(String used, String limit) {
    return '$used of $limit used';
  }

  @override
  String storageAttachments(String used, String limit) {
    return 'Attachments: $used of $limit';
  }

  @override
  String storageUsedNoLimit(String used) {
    return '$used used, no limit';
  }

  @override
  String storageAttachmentsNoLimit(String used) {
    return 'Attachments: $used, no limit';
  }

  @override
  String get language => 'Language';

  @override
  String get languagePhone => 'Phone\'s language';

  @override
  String get taglineNotes => 'Notes, lists and notebooks';

  @override
  String get taglineTasks => 'To-dos, reminders and lists';

  @override
  String get taglineFitness => 'Activity, workouts and health';

  @override
  String get taglineContacts => 'Your address book';

  @override
  String get taglineClock => 'Alarms, timer, stopwatch and world clock';

  @override
  String get taglineTime => 'Time tracking for work and projects';

  @override
  String get taglineQuests => 'Daily quests for your goals, with XP and levels';

  @override
  String get taglineCalendar => 'Events, reminders and planning';

  @override
  String get taglineBrowser => 'Private web browsing';

  @override
  String get taglinePhone => 'Calls, call log and blocking';

  @override
  String get taglineCamera => 'Photos and videos, encrypted as you take them';

  @override
  String get taglineGallery => 'Your photos and albums';

  @override
  String get taglineHome => 'Your smart home';

  @override
  String get taglineFamily => 'Your family circle and shared locations';

  @override
  String get taglineMeds => 'Medications, doses and reminders';

  @override
  String get taglineKeyboard => 'A private keyboard';

  @override
  String get taglineAuthenticator => 'Two-step sign-in codes';

  @override
  String planName(String name) {
    return 'Plan: $name';
  }

  @override
  String get planFree => 'Free';

  @override
  String planRenews(String date) {
    return 'Renews $date';
  }

  @override
  String planEnds(String date) {
    return 'Ends $date';
  }

  @override
  String get planPaymentProblem =>
      'Payment problem. Update your payment method to keep your plan';

  @override
  String get planSeePlans => 'See plans';

  @override
  String get crashReports => 'Crash reports';

  @override
  String get crashReportsOff => 'Off';

  @override
  String get crashReportsAsk => 'Ask me before sending';

  @override
  String get crashReportsKeep => 'Keep on this phone so I can copy them';

  @override
  String get crashReportsAutomatic => 'Send automatically';

  @override
  String get crashReportsIntro =>
      'When the app hits a bug, it can write a short technical report to help fix it. This is off unless you turn it on.';

  @override
  String get crashReportsIncluded =>
      'Included: the app and its version, Android or iPhone, the date, the kind of error and where in the code it happened.';

  @override
  String get crashReportsNeverIncluded =>
      'Never included: anything you wrote or saved, your email or account, your phone\'s name or id, or your location.';

  @override
  String get crashReportsSaved => 'Saved reports';

  @override
  String get crashReportsNone => 'No saved reports';

  @override
  String crashReportHappened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Happened $count times',
      one: 'Happened once',
    );
    return '$_temp0';
  }

  @override
  String get crashReportSend => 'Send';

  @override
  String get crashReportSent => 'Report sent. Thank you!';

  @override
  String get crashReportNotSent => 'Couldn\'t send it. It\'s kept for later.';

  @override
  String get crashReportCopied => 'Report copied';

  @override
  String get crashReportsDeleteAll => 'Delete all';

  @override
  String get crashReportWholeReport =>
      'This is the whole report, exactly as it would leave your phone.';

  @override
  String get crashReportPromptTitle => 'The app hit a problem';

  @override
  String get crashReportPromptBody =>
      'Send a crash report to help fix it? It holds no personal data.';

  @override
  String get crashReportView => 'View report';

  @override
  String get crashReportDontSend => 'Don\'t send';

  @override
  String get neverEvenAfterClosing => 'Never, even after closing the app';

  @override
  String get neverStaysOpenAfterClosing =>
      'Never, stays open even after closing';

  @override
  String get needsAScreenLock => 'Needs a screen lock on your phone';

  @override
  String keepAppOpenQuestion(String appName) {
    return 'Keep $appName open?';
  }

  @override
  String keepAppOpenExplanation(String appName) {
    return '$appName will open without your password or fingerprint, even after you close it or restart the phone. Anyone who can unlock your phone can open it, so choose this only if your phone\'s screen lock is yours alone.\n\nYour data stays encrypted on the phone and on our servers. Changing your password, a new recovery key, exporting your data and deleting your account still ask for your password.';
  }

  @override
  String get keepOpen => 'Keep open';

  @override
  String enterYourPasswordToKeepOpen(String appName) {
    return 'Enter your password to keep $appName open.';
  }

  @override
  String get enterYourPasswordToExport =>
      'Enter your password to export your data.';

  @override
  String get plansTitle => 'Plans';

  @override
  String get plansPlusName => 'Plus';

  @override
  String get plansPlusTagline => 'More room in every Zero-Trust app';

  @override
  String get plansPlusSynced => '1 GB of synced data, up from 50 MB';

  @override
  String get plansPlusFiles => '20 GB of attached files, up from 500 MB';

  @override
  String get plansPlusAllApps => 'One subscription covers every app';

  @override
  String get plansPlusSameEncryption =>
      'The same end-to-end encryption as Free';

  @override
  String plansMonthly(String price) {
    return '$price a month';
  }

  @override
  String plansYearly(String price) {
    return '$price a year';
  }

  @override
  String get plansNotAvailable => 'Plus can\'t be bought here yet.';

  @override
  String plansYouHave(String name) {
    return 'You have $name. Thank you for supporting Zero-Trust.';
  }

  @override
  String plansGranted(String name) {
    return '$name was given to you by Zero-Trust.';
  }

  @override
  String get plansManage => 'Manage subscription';

  @override
  String get plansRestore => 'Restore purchases';

  @override
  String get plansFinePrint =>
      'Renews automatically. No free trial. Cancel any time and keep Plus until the end of the period you\'ve paid for. Everything that\'s free stays free.';

  @override
  String get plansThanks => 'Thank you! Plus is on.';

  @override
  String get plansPending =>
      'Payment pending. Plus turns on as soon as the store confirms it.';

  @override
  String get plansFailed =>
      'The purchase didn\'t go through. Please try again.';

  @override
  String get rememberOnThisBrowser => 'Remember on this browser';

  @override
  String get rememberOnThisBrowserOff =>
      'Off: your password is asked every time you open this page';

  @override
  String get rememberOnThisBrowserOn =>
      'On: opens without your password on this browser';

  @override
  String rememberOnThisBrowserQuestion(String appName) {
    return 'Remember $appName on this browser?';
  }

  @override
  String rememberOnThisBrowserExplanation(String appName) {
    return '$appName will open on this browser without your password, even after you close the tab or restart the computer. Anyone who can use this browser can then open your data, so never turn this on on a shared or public computer.\n\nYour data stays encrypted in the browser and on our servers. Changing your password, a new recovery key, exporting your data and deleting your account still ask for your password.';
  }

  @override
  String get remember => 'Remember';

  @override
  String enterYourPasswordToRemember(String appName) {
    return 'Enter your password to remember $appName on this browser.';
  }

  @override
  String get rememberNotAvailable =>
      'This browser can\'t keep the key safely here. Open the app over a secure (https) connection.';

  @override
  String get neverRememberedOnThisBrowser =>
      'Never, remembered on this browser';

  @override
  String get signOutAndRemoveData =>
      'Sign out and remove data from this browser';

  @override
  String get forSharedOrPublicComputers => 'For shared or public computers';

  @override
  String get removeYourDataFromThisBrowser =>
      'Remove your data from this browser?';

  @override
  String get removeFromBrowserExplanation =>
      'You\'ll be signed out, and the encrypted copy kept in this browser will be deleted, along with your settings here. Changes that haven\'t synced yet will be lost.\n\nYour account and everything already synced stay safe. Sign in again any time to get it back.';

  @override
  String get signOutAndRemove => 'Sign out and remove';

  @override
  String get accountDeletionScheduledTitle =>
      'Your account is set to be deleted';

  @override
  String accountDeletionScheduledBody(String date) {
    return 'On $date your account and your data in every Zero-Trust app will be deleted for good. Until then you can keep it.';
  }

  @override
  String accountDeletionScheduledTile(String date) {
    return 'Will be deleted on $date';
  }

  @override
  String get keepMyAccount => 'Keep my account';

  @override
  String get deleteAsPlanned => 'Delete as planned';

  @override
  String get accountKept => 'Your account won\'t be deleted.';

  @override
  String get accountTooLateToKeep =>
      'It\'s too late to keep this account: it\'s being deleted now.';

  @override
  String get accountDeletionRequestedTitle => 'Account deletion scheduled';

  @override
  String accountDeletionRequestedBody(String date) {
    return 'Your account will be deleted on $date. Changed your mind? Sign in to any Zero-Trust app before then and tap Keep my account, or use the link we emailed you.';
  }

  @override
  String get ok => 'OK';

  @override
  String get changeEmail => 'Change email';

  @override
  String get changeEmailSubtitle => 'Sign in with a different address';

  @override
  String get changeEmailIntro =>
      'Your data stays encrypted with your password, as before. Only the address you sign in with changes, in every Zero-Trust app.';

  @override
  String get newEmail => 'New email';

  @override
  String get sendCode => 'Send code';

  @override
  String enterEmailCode(String email) {
    return 'Enter the 6-digit code we sent to $email.';
  }

  @override
  String get emailCode => 'Code';

  @override
  String get changeEmailConfirm => 'Change email';

  @override
  String get sendNewCode => 'Send a new code';

  @override
  String emailChangedTo(String email) {
    return 'Your account now signs in with $email.';
  }

  @override
  String get errEmailInvalid => 'That doesn\'t look like an email address.';

  @override
  String get errEmailSame => 'That is already your account\'s email.';

  @override
  String get errEmailInUse => 'That email already has a Zero-Trust account.';

  @override
  String get errEmailCodeWrong =>
      'That code isn\'t right. Check the email and try again.';

  @override
  String get errEmailCodeExpired => 'The code expired. Send a new one.';

  @override
  String get appUpdates => 'App updates';

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String youHaveTheLatestVersion(String version) {
    return 'You have the latest version ($version)';
  }

  @override
  String updateAvailableVersion(String version) {
    return 'Version $version is available. Tap to update.';
  }

  @override
  String get couldNotCheckForUpdates =>
      'Couldn\'t check for updates. Tap to try again.';

  @override
  String get noReleaseYet => 'No release on GitHub yet';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkForUpdatesSubtitle =>
      'Once a day, asks GitHub for the newest version number. Nothing about you or your data is sent.';

  @override
  String get getUpdatesWithObtainium => 'Get updates with Obtainium';

  @override
  String get obtainiumSubtitle =>
      'A free app that installs updates straight from GitHub';

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String updateAvailableBody(String app, String version, String installed) {
    return '$app $version is ready. You have $installed.';
  }

  @override
  String get updateHowItInstalls =>
      'Your browser downloads the update; open it to install. Android installs it only if it is signed by the same developer as this app.';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get downloadUpdate => 'Download';

  @override
  String get couldNotOpenLink => 'Couldn\'t open the link.';

  @override
  String get backUpEverything => 'Back up everything';

  @override
  String get backUpEverythingSubtitle =>
      'One encrypted file with your data from every Zero-Trust app';

  @override
  String get restoreFromBackup => 'Restore from a backup';

  @override
  String get restoreFromBackupSubtitle =>
      'Into this account, on any phone. Newer changes are kept.';

  @override
  String get backUp => 'Back up';

  @override
  String get chooseBackupPassword => 'Choose a backup password';

  @override
  String get backupPasswordExplained =>
      'The backup file is encrypted with this password. You need it to restore, and nobody can recover it for you. Your account password works too.';

  @override
  String get backupPassword => 'Backup password';

  @override
  String get repeatBackupPassword => 'Repeat the backup password';

  @override
  String get enterYourPasswordToBackUp =>
      'Enter your account password to read your data from every app.';

  @override
  String backingUp(String app) {
    return 'Backing up $app…';
  }

  @override
  String backupSaved(int items, int apps) {
    String _temp0 = intl.Intl.pluralLogic(
      items,
      locale: localeName,
      other: '$items items',
      one: '1 item',
    );
    String _temp1 = intl.Intl.pluralLogic(
      apps,
      locale: localeName,
      other: '$apps apps',
      one: '1 app',
    );
    return 'Backup saved: $_temp0 from $_temp1.';
  }

  @override
  String backupItemsUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items couldn\'t be opened and aren\'t in it.',
      one: '1 item couldn\'t be opened and isn\'t in it.',
    );
    return '$_temp0';
  }

  @override
  String backupFilesMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attached files couldn\'t be read and aren\'t in it.',
      one: '1 attached file couldn\'t be read and isn\'t in it.',
    );
    return '$_temp0';
  }

  @override
  String get enterBackupPassword => 'Enter the backup password';

  @override
  String get openBackup => 'Open';

  @override
  String get wrongBackupPassword => 'Wrong backup password.';

  @override
  String get notABackupFile => 'This isn\'t a Zero-Trust backup file.';

  @override
  String get backupFromNewerVersion =>
      'This backup is from a newer version. Update the app first.';

  @override
  String get backupDamaged => 'The backup file is damaged or incomplete.';

  @override
  String get restoreBackupQuestion => 'Restore this backup?';

  @override
  String restoreBackupSummary(String date, int items, String apps) {
    String _temp0 = intl.Intl.pluralLogic(
      items,
      locale: localeName,
      other: '$items items',
      one: '1 item',
    );
    return 'Backup from $date: $_temp0 from $apps. Anything you changed or deleted since then stays as it is.';
  }

  @override
  String get restore => 'Restore';

  @override
  String get enterYourPasswordToRestore =>
      'Enter your account password to restore into this account.';

  @override
  String restoring(String app) {
    return 'Restoring $app…';
  }

  @override
  String backupRestored(int restored, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      restored,
      locale: localeName,
      other: '$restored items',
      one: '1 item',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped were already up to date.',
      one: '1 was already up to date.',
      zero: '',
    );
    return 'Restored $_temp0. $_temp1';
  }

  @override
  String handoffSignInWith(String app) {
    return 'Sign in with $app';
  }

  @override
  String get handoffSignInWithAnother => 'Sign in with another ZT app';

  @override
  String handoffUnlockWith(String app) {
    return 'Unlock with $app';
  }

  @override
  String get handoffUnlockWithAnother => 'Unlock with another ZT app';

  @override
  String get handoffPickApp => 'Use the account from';

  @override
  String handoffWaiting(String app) {
    return 'Confirm in $app…';
  }

  @override
  String handoffAskSignIn(String app) {
    return 'Sign in to $app?';
  }

  @override
  String handoffAskUnlock(String app) {
    return 'Unlock $app?';
  }

  @override
  String handoffAskBody(String app, String email) {
    return '$app will open with your Zero-Trust account ($email) on this phone, without the password. Only Zero-Trust apps can ask for this.';
  }

  @override
  String handoffConfirm(String app) {
    return 'Confirm it\'s you to share your account with $app.';
  }

  @override
  String get handoffAllow => 'Allow';

  @override
  String handoffDeclined(String app) {
    return '$app didn\'t share the account.';
  }

  @override
  String handoffSignedOut(String app) {
    return '$app isn\'t signed in. Sign in there first, or use your password here.';
  }

  @override
  String handoffFailed(String app) {
    return '$app couldn\'t share the account. Try again, or use your password.';
  }

  @override
  String handoffNoAnswer(String app) {
    return 'No answer came from $app. Try again.';
  }

  @override
  String get handoffWrongAccount =>
      'That app is signed in to a different account.';
}
