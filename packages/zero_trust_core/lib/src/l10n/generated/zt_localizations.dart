import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'zt_localizations_en.dart';
import 'zt_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ZtLocalizations
/// returned by `ZtLocalizations.of(context)`.
///
/// Applications need to include `ZtLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/zt_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ZtLocalizations.localizationsDelegates,
///   supportedLocales: ZtLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ZtLocalizations.supportedLocales
/// property.
abstract class ZtLocalizations {
  ZtLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ZtLocalizations? of(BuildContext context) {
    return Localizations.of<ZtLocalizations>(context, ZtLocalizations);
  }

  static const LocalizationsDelegate<ZtLocalizations> delegate =
      _ZtLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he')
  ];

  /// No description provided for @unlockWithBiometricsQuestion.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics?'**
  String get unlockWithBiometricsQuestion;

  /// No description provided for @useYourFingerprintOrFaceTo.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint or face to open the app on this phone. You can change this in Settings.'**
  String get useYourFingerprintOrFaceTo;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @sentAgainCheckYourInboxAnd.
  ///
  /// In en, this message translates to:
  /// **'Sent again. Check your inbox and spam folder.'**
  String get sentAgainCheckYourInboxAnd;

  /// No description provided for @signUpIntro.
  ///
  /// In en, this message translates to:
  /// **'One account for every Zero-Trust app. Your password never leaves this device.'**
  String get signUpIntro;

  /// No description provided for @signInWithYourZeroTrust.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Zero-Trust account.'**
  String get signInWithYourZeroTrust;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get enterYourPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get passwordsDontMatch;

  /// No description provided for @resendConfirmationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend confirmation email'**
  String get resendConfirmationEmail;

  /// No description provided for @creatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account'**
  String get creatingAccount;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get signingIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @iAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get iAlreadyHaveAnAccount;

  /// No description provided for @createAZeroTrustAccount.
  ///
  /// In en, this message translates to:
  /// **'Create a Zero-Trust account'**
  String get createAZeroTrustAccount;

  /// No description provided for @forgotPasswordQuestion.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordQuestion;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @unlockWithBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get unlockWithBiometrics;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPassword;

  /// No description provided for @yourDataIsEncryptedWithYour.
  ///
  /// In en, this message translates to:
  /// **'Your data is encrypted with your password, so resetting it needs two things: a link we email you, and the recovery key you saved when you created your account.'**
  String get yourDataIsEncryptedWithYour;

  /// No description provided for @emailMeAResetLink.
  ///
  /// In en, this message translates to:
  /// **'Email me a reset link'**
  String get emailMeAResetLink;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @enterTheRecoveryKeyYouSaved.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery key you saved when you created your account, then choose a new password.'**
  String get enterTheRecoveryKeyYouSaved;

  /// No description provided for @recoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get recoveryKey;

  /// No description provided for @enterYourRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery key.'**
  String get enterYourRecoveryKey;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @saveYourRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery key'**
  String get saveYourRecoveryKey;

  /// No description provided for @thisKeyIsTheOnlyWay.
  ///
  /// In en, this message translates to:
  /// **'This key is the only way back into your data if you forget your password. We can\'t reset it for you, because we never see your password or your data.'**
  String get thisKeyIsTheOnlyWay;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copiedStoreItSomewhereSafeAnd.
  ///
  /// In en, this message translates to:
  /// **'Copied. Store it somewhere safe and offline.'**
  String get copiedStoreItSomewhereSafeAnd;

  /// No description provided for @iSavedMyRecoveryKeySomewhere.
  ///
  /// In en, this message translates to:
  /// **'I saved my recovery key somewhere safe'**
  String get iSavedMyRecoveryKeySomewhere;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @onlyYouCanReadYourData.
  ///
  /// In en, this message translates to:
  /// **'Only you can read your data'**
  String get onlyYouCanReadYourData;

  /// No description provided for @everythingIsEncryptedOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Everything is encrypted on this phone before it\'s saved or synced. We never see your password, so we can\'t read your data, and neither can anyone who breaks into our servers.'**
  String get everythingIsEncryptedOnThisPhone;

  /// No description provided for @keepYourRecoveryKeySafe.
  ///
  /// In en, this message translates to:
  /// **'Keep your recovery key safe'**
  String get keepYourRecoveryKeySafe;

  /// No description provided for @whenYouCreateYourAccountYou.
  ///
  /// In en, this message translates to:
  /// **'When you create your account you get a recovery key. It\'s the only way back in if you forget your password, because we can\'t reset it for you. Write it down or keep it in a password manager.'**
  String get whenYouCreateYourAccountYou;

  /// No description provided for @unlockWithATouch.
  ///
  /// In en, this message translates to:
  /// **'Unlock with a touch'**
  String get unlockWithATouch;

  /// No description provided for @turnOnFingerprintOrFaceUnlock.
  ///
  /// In en, this message translates to:
  /// **'Turn on fingerprint or face unlock after you sign in. It stays on this phone, and your password still works everywhere. One account opens every Zero-Trust app.'**
  String get turnOnFingerprintOrFaceUnlock;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @encryptedOnYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on your phone'**
  String get encryptedOnYourPhone;

  /// No description provided for @everythingYouWriteIsEncryptedOn.
  ///
  /// In en, this message translates to:
  /// **'Everything you write is encrypted on this device before it goes anywhere, with AES-256, the standard banks and governments use. Our servers only ever store scrambled data they can\'t read.'**
  String get everythingYouWriteIsEncryptedOn;

  /// No description provided for @onlyYourPasswordCanUnlockIt.
  ///
  /// In en, this message translates to:
  /// **'Only your password can unlock it'**
  String get onlyYourPasswordCanUnlockIt;

  /// No description provided for @yourEncryptionKeyIsMadeFrom.
  ///
  /// In en, this message translates to:
  /// **'Your encryption key is made from your password on your phone. The password itself never leaves the device: we receive a separate value derived from it, which can sign you in but can\'t decrypt anything. Not us, not our hosting provider, and not anyone who breaks into our servers can read your data. (An account made with an older app version sends its password once more, the first time it signs in after updating, to switch over to this.)'**
  String get yourEncryptionKeyIsMadeFrom;

  /// No description provided for @yourRecoveryKeyIsTheOnly.
  ///
  /// In en, this message translates to:
  /// **'Your recovery key is the only backup'**
  String get yourRecoveryKeyIsTheOnly;

  /// No description provided for @becauseWeCantReadYourData.
  ///
  /// In en, this message translates to:
  /// **'Because we can\'t read your data, we can\'t reset your password for you either. Your recovery key is the one way back in if you forget your password. Keep it somewhere safe, offline. You can make a new one in Settings at any time.'**
  String get becauseWeCantReadYourData;

  /// No description provided for @protectedOnTheDeviceToo.
  ///
  /// In en, this message translates to:
  /// **'Protected on the device too'**
  String get protectedOnTheDeviceToo;

  /// No description provided for @theCopyKeptOnYourPhone.
  ///
  /// In en, this message translates to:
  /// **'The copy kept on your phone is encrypted as well, and locks after the time you choose under Auto-lock. Fingerprint or face unlock keeps your key in the phone\'s secure hardware.'**
  String get theCopyKeptOnYourPhone;

  /// No description provided for @tamperProofSync.
  ///
  /// In en, this message translates to:
  /// **'Tamper-proof sync'**
  String get tamperProofSync;

  /// No description provided for @eachItemIsSignedWithA.
  ///
  /// In en, this message translates to:
  /// **'Each item is signed with a key only your devices have, so a changed or swapped item on the server is spotted and refused rather than shown to you.'**
  String get eachItemIsSignedWithA;

  /// No description provided for @oneAccountSeparateKeys.
  ///
  /// In en, this message translates to:
  /// **'One account, separate keys'**
  String get oneAccountSeparateKeys;

  /// No description provided for @theSameAccountWorksInEvery.
  ///
  /// In en, this message translates to:
  /// **'The same account works in every Zero-Trust app, but each app encrypts with its own key, derived from yours.'**
  String get theSameAccountWorksInEvery;

  /// No description provided for @whatWeCanSee.
  ///
  /// In en, this message translates to:
  /// **'What we can see'**
  String get whatWeCanSee;

  /// No description provided for @yourEmailAddressWhenYouSign.
  ///
  /// In en, this message translates to:
  /// **'Your email address, when you sign in, how many items you store and their size, and when they change. Never what they say.'**
  String get yourEmailAddressWhenYouSign;

  /// No description provided for @breachedPasswordCheck.
  ///
  /// In en, this message translates to:
  /// **'Breached-password check'**
  String get breachedPasswordCheck;

  /// No description provided for @whenYouChooseANewPassword.
  ///
  /// In en, this message translates to:
  /// **'When you choose a new password, we check it against known data breaches without sending it: only the first 5 characters of a one-way fingerprint go to Have I Been Pwned, and the match is done on your phone.'**
  String get whenYouChooseANewPassword;

  /// No description provided for @deleteEverythingAnyTime.
  ///
  /// In en, this message translates to:
  /// **'Delete everything, any time'**
  String get deleteEverythingAnyTime;

  /// No description provided for @deletingYourAccountUnderSettingsDanger.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account under Settings → Danger zone removes your data from our servers in every Zero-Trust app.'**
  String get deletingYourAccountUnderSettingsDanger;

  /// No description provided for @howYourDataIsProtected.
  ///
  /// In en, this message translates to:
  /// **'How your data is protected'**
  String get howYourDataIsProtected;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @notSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// No description provided for @oneAccountForEveryApp.
  ///
  /// In en, this message translates to:
  /// **'One account for every Zero-Trust app'**
  String get oneAccountForEveryApp;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get autoLock;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get lockNow;

  /// No description provided for @newRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'New recovery key'**
  String get newRecoveryKey;

  /// No description provided for @yourCurrentRecoveryKeyWillStop.
  ///
  /// In en, this message translates to:
  /// **'Your current recovery key will stop working'**
  String get yourCurrentRecoveryKeyWillStop;

  /// No description provided for @endToEndEncryptionInPlain.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption, in plain words'**
  String get endToEndEncryptionInPlain;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @endToEndEncryptedWeCant.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted. We can\'t read your data.'**
  String get endToEndEncryptedWeCant;

  /// No description provided for @helpAndFeedback.
  ///
  /// In en, this message translates to:
  /// **'Help and feedback'**
  String get helpAndFeedback;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get termsOfUse;

  /// No description provided for @openSourceLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get openSourceLicences;

  /// No description provided for @otherZeroTrustApps.
  ///
  /// In en, this message translates to:
  /// **'Other Zero-Trust apps'**
  String get otherZeroTrustApps;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deletesYourDataInEveryZero.
  ///
  /// In en, this message translates to:
  /// **'Deletes your data in every Zero-Trust app'**
  String get deletesYourDataInEveryZero;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @immediatelyWhenYouLeaveTheApp.
  ///
  /// In en, this message translates to:
  /// **'Immediately when you leave the app'**
  String get immediatelyWhenYouLeaveTheApp;

  /// No description provided for @immediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// No description provided for @passwordChangedYourOtherDevicesWere.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Your other devices were signed out.'**
  String get passwordChangedYourOtherDevicesWere;

  /// No description provided for @enterYourPasswordYourCurrentRecovery.
  ///
  /// In en, this message translates to:
  /// **'Enter your password. Your current recovery key will stop working.'**
  String get enterYourPasswordYourCurrentRecovery;

  /// No description provided for @deleteAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountQuestion;

  /// No description provided for @thisPermanentlyDeletesYourAccountAnd.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and your data in every Zero-Trust app. It can\'t be undone.'**
  String get thisPermanentlyDeletesYourAccountAnd;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @useWallpaperColours.
  ///
  /// In en, this message translates to:
  /// **'Use wallpaper colours'**
  String get useWallpaperColours;

  /// No description provided for @matchYourPhonesThemeInsteadOf.
  ///
  /// In en, this message translates to:
  /// **'Match your phone\'s theme instead of the app\'s'**
  String get matchYourPhonesThemeInsteadOf;

  /// No description provided for @enterYourPasswordToTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to turn on fingerprint or face unlock on this device.'**
  String get enterYourPasswordToTurnOn;

  /// No description provided for @fingerprintOrFaceOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint or face, on this device only'**
  String get fingerprintOrFaceOnThisDevice;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @notSyncedYet.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get notSyncedYet;

  /// No description provided for @syncedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get syncedJustNow;

  /// No description provided for @exportMyDataQuestion.
  ///
  /// In en, this message translates to:
  /// **'Export my data?'**
  String get exportMyDataQuestion;

  /// No description provided for @youGetOneZipFileWith.
  ///
  /// In en, this message translates to:
  /// **'You get one ZIP file with everything in this app, readable by any computer. It isn\'t encrypted, so anyone who gets the file can read it. Keep it somewhere safe.'**
  String get youGetOneZipFileWith;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportMyData.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get exportMyData;

  /// No description provided for @aZipOfEverythingInThis.
  ///
  /// In en, this message translates to:
  /// **'A ZIP of everything in this app, not encrypted'**
  String get aZipOfEverythingInThis;

  /// No description provided for @exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting'**
  String get exporting;

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {count}'**
  String pageOf(int page, int count);

  /// No description provided for @appIsLocked.
  ///
  /// In en, this message translates to:
  /// **'{appName} is locked'**
  String appIsLocked(String appName);

  /// No description provided for @unlocking.
  ///
  /// In en, this message translates to:
  /// **'Unlocking'**
  String get unlocking;

  /// No description provided for @checkEmailForResetLink.
  ///
  /// In en, this message translates to:
  /// **'Check {email} for a reset link. Open it on this device, then enter your recovery key.'**
  String checkEmailForResetLink(String email);

  /// No description provided for @recoveryKeySpelled.
  ///
  /// In en, this message translates to:
  /// **'Recovery key: {spelled}'**
  String recoveryKeySpelled(String spelled);

  /// No description provided for @zeroTrustMeans.
  ///
  /// In en, this message translates to:
  /// **'Zero-trust means you don\'t have to trust us with your data. Here\'s how {appName} keeps it private.'**
  String zeroTrustMeans(String appName);

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @taglineSameAccount.
  ///
  /// In en, this message translates to:
  /// **'{tagline} · same account'**
  String taglineSameAccount(String tagline);

  /// No description provided for @autoLockAfterMinutesIdle.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{After 1 min in the background or idle} other{After {minutes} min in the background or idle}}'**
  String autoLockAfterMinutesIdle(int minutes);

  /// No description provided for @autoLockAfterSecondsIdle.
  ///
  /// In en, this message translates to:
  /// **'After {seconds} s in the background or idle'**
  String autoLockAfterSecondsIdle(int seconds);

  /// No description provided for @afterMinutes.
  ///
  /// In en, this message translates to:
  /// **'After {minutes} min'**
  String afterMinutes(int minutes);

  /// No description provided for @afterSeconds.
  ///
  /// In en, this message translates to:
  /// **'After {seconds} s'**
  String afterSeconds(int seconds);

  /// No description provided for @syncedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {minutes} min ago'**
  String syncedMinutesAgo(int minutes);

  /// No description provided for @syncedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{Synced 1 hour ago} other{Synced {hours} hours ago}}'**
  String syncedHoursAgo(int hours);

  /// No description provided for @syncedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Synced yesterday} other{Synced {days} days ago}}'**
  String syncedDaysAgo(int days);

  /// No description provided for @attachmentsNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attached file couldn\'t be included. Try again when online.} other{{count} attached files couldn\'t be included. Try again when online.}}'**
  String attachmentsNotIncluded(int count);

  /// No description provided for @strengthVeryWeak.
  ///
  /// In en, this message translates to:
  /// **'Very weak'**
  String get strengthVeryWeak;

  /// No description provided for @strengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strengthWeak;

  /// No description provided for @strengthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get strengthFair;

  /// No description provided for @strengthGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get strengthGood;

  /// No description provided for @strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthStrong;

  /// No description provided for @enterAPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a password.'**
  String get enterAPassword;

  /// No description provided for @tipNoEmail.
  ///
  /// In en, this message translates to:
  /// **'Don\'t use your email in it.'**
  String get tipNoEmail;

  /// No description provided for @tipCommonWords.
  ///
  /// In en, this message translates to:
  /// **'Avoid common words and passwords.'**
  String get tipCommonWords;

  /// No description provided for @tipRepeated.
  ///
  /// In en, this message translates to:
  /// **'Avoid repeated characters like \"aaa\".'**
  String get tipRepeated;

  /// No description provided for @tipSequences.
  ///
  /// In en, this message translates to:
  /// **'Avoid sequences like \"1234\" or \"qwerty\".'**
  String get tipSequences;

  /// No description provided for @tipYears.
  ///
  /// In en, this message translates to:
  /// **'Avoid years and dates.'**
  String get tipYears;

  /// No description provided for @tipLonger.
  ///
  /// In en, this message translates to:
  /// **'Make it longer: a few unrelated words work well.'**
  String get tipLonger;

  /// No description provided for @tipMix.
  ///
  /// In en, this message translates to:
  /// **'Mix in words, numbers or symbols.'**
  String get tipMix;

  /// No description provided for @passwordBreached.
  ///
  /// In en, this message translates to:
  /// **'This password has appeared in data breaches, so attackers try it first. Choose a different one.'**
  String get passwordBreached;

  /// No description provided for @errOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get errOffline;

  /// No description provided for @errInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'That email and password don\'t match.'**
  String get errInvalidCredentials;

  /// No description provided for @errEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first: open the link we sent you.'**
  String get errEmailNotConfirmed;

  /// No description provided for @errKeyMismatch.
  ///
  /// In en, this message translates to:
  /// **'This password can\'t unlock your data. Use your recovery key to reset it.'**
  String get errKeyMismatch;

  /// No description provided for @errBiometricChanged.
  ///
  /// In en, this message translates to:
  /// **'Your fingerprints or face changed, so biometric unlock was turned off. Unlock with your password, then turn it back on in Settings.'**
  String get errBiometricChanged;

  /// No description provided for @errRecoveryKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'That recovery key isn\'t valid. Check it for typos.'**
  String get errRecoveryKeyInvalid;

  /// No description provided for @errSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Your session ended. Sign in again.'**
  String get errSessionEnded;

  /// No description provided for @errFileTooLargeUpload.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to upload.'**
  String get errFileTooLargeUpload;

  /// No description provided for @errAttachmentNotFound.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'t available yet. It will appear once the device that added it is back online.'**
  String get errAttachmentNotFound;

  /// No description provided for @errAttachmentCorrupt.
  ///
  /// In en, this message translates to:
  /// **'This file was damaged or changed on the server, so it wasn\'t opened.'**
  String get errAttachmentCorrupt;

  /// No description provided for @errNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'This was changed in a newer version of the app. Update the app to edit it.'**
  String get errNewerVersion;

  /// No description provided for @errLocalStoreUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Data on this device couldn\'t be opened. It will be downloaded again.'**
  String get errLocalStoreUnreadable;

  /// No description provided for @errVaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Unlock the app first.'**
  String get errVaultLocked;

  /// No description provided for @errTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes and try again.'**
  String get errTooMany;

  /// No description provided for @errServerDown.
  ///
  /// In en, this message translates to:
  /// **'Our server isn\'t responding right now. Your data is safe; try again soon.'**
  String get errServerDown;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Check your connection and try again.'**
  String get errGeneric;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get enterValidEmail;

  /// No description provided for @useAtLeast12.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters.'**
  String get useAtLeast12;

  /// No description provided for @tipDefaultLonger.
  ///
  /// In en, this message translates to:
  /// **'Make it longer.'**
  String get tipDefaultLonger;

  /// No description provided for @syncFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync. Tap to retry'**
  String get syncFailedRetry;

  /// No description provided for @errConfirmationSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to {email}. Open it, then sign in.'**
  String errConfirmationSent(String email);

  /// No description provided for @errFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large. The limit is {megabytes} MB.'**
  String errFileTooLarge(int megabytes);

  /// No description provided for @tooEasyToGuess.
  ///
  /// In en, this message translates to:
  /// **'Too easy to guess. {hint}'**
  String tooEasyToGuess(String hint);

  /// No description provided for @itemsUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item couldn\'t be read} other{{count} items couldn\'t be read}}'**
  String itemsUnreadable(int count);

  /// No description provided for @storageFull.
  ///
  /// In en, this message translates to:
  /// **'Storage full. New changes stay on this device until you delete something'**
  String get storageFull;

  /// No description provided for @itemsTooLarge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is too large to sync} other{{count} items are too large to sync}}'**
  String itemsTooLarge(int count);

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} used'**
  String storageUsed(String used, String limit);

  /// No description provided for @storageAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments: {used} of {limit}'**
  String storageAttachments(String used, String limit);

  /// Settings row and dialog title for the app's language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Language choice that follows the phone's own language.
  ///
  /// In en, this message translates to:
  /// **'Phone\'s language'**
  String get languagePhone;

  /// No description provided for @taglineNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes, lists and notebooks'**
  String get taglineNotes;

  /// No description provided for @taglineTasks.
  ///
  /// In en, this message translates to:
  /// **'To-dos, reminders and lists'**
  String get taglineTasks;

  /// No description provided for @taglineFitness.
  ///
  /// In en, this message translates to:
  /// **'Activity, workouts and health'**
  String get taglineFitness;

  /// No description provided for @taglineContacts.
  ///
  /// In en, this message translates to:
  /// **'Your address book'**
  String get taglineContacts;

  /// Settings row and screen title for opt-in crash reports.
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get crashReports;

  /// No description provided for @crashReportsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get crashReportsOff;

  /// No description provided for @crashReportsAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask me before sending'**
  String get crashReportsAsk;

  /// Choice shown instead of 'Ask me before sending' when the app has nowhere to send reports yet.
  ///
  /// In en, this message translates to:
  /// **'Keep on this phone so I can copy them'**
  String get crashReportsKeep;

  /// No description provided for @crashReportsAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Send automatically'**
  String get crashReportsAutomatic;

  /// No description provided for @crashReportsIntro.
  ///
  /// In en, this message translates to:
  /// **'When the app hits a bug, it can write a short technical report to help fix it. This is off unless you turn it on.'**
  String get crashReportsIntro;

  /// No description provided for @crashReportsIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included: the app and its version, Android or iPhone, the date, the kind of error and where in the code it happened.'**
  String get crashReportsIncluded;

  /// No description provided for @crashReportsNeverIncluded.
  ///
  /// In en, this message translates to:
  /// **'Never included: anything you wrote or saved, your email or account, your phone\'s name or id, or your location.'**
  String get crashReportsNeverIncluded;

  /// No description provided for @crashReportsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved reports'**
  String get crashReportsSaved;

  /// No description provided for @crashReportsNone.
  ///
  /// In en, this message translates to:
  /// **'No saved reports'**
  String get crashReportsNone;

  /// No description provided for @crashReportHappened.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Happened once} other{Happened {count} times}}'**
  String crashReportHappened(int count);

  /// No description provided for @crashReportSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get crashReportSend;

  /// No description provided for @crashReportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent. Thank you!'**
  String get crashReportSent;

  /// No description provided for @crashReportNotSent.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send it. It\'s kept for later.'**
  String get crashReportNotSent;

  /// No description provided for @crashReportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied'**
  String get crashReportCopied;

  /// No description provided for @crashReportsDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get crashReportsDeleteAll;

  /// No description provided for @crashReportWholeReport.
  ///
  /// In en, this message translates to:
  /// **'This is the whole report, exactly as it would leave your phone.'**
  String get crashReportWholeReport;

  /// No description provided for @crashReportPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'The app hit a problem'**
  String get crashReportPromptTitle;

  /// No description provided for @crashReportPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Send a crash report to help fix it? It holds no personal data.'**
  String get crashReportPromptBody;

  /// No description provided for @crashReportView.
  ///
  /// In en, this message translates to:
  /// **'View report'**
  String get crashReportView;

  /// No description provided for @crashReportDontSend.
  ///
  /// In en, this message translates to:
  /// **'Don\'t send'**
  String get crashReportDontSend;
}

class _ZtLocalizationsDelegate extends LocalizationsDelegate<ZtLocalizations> {
  const _ZtLocalizationsDelegate();

  @override
  Future<ZtLocalizations> load(Locale locale) {
    return SynchronousFuture<ZtLocalizations>(lookupZtLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_ZtLocalizationsDelegate old) => false;
}

ZtLocalizations lookupZtLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ZtLocalizationsEn();
    case 'he':
      return ZtLocalizationsHe();
  }

  throw FlutterError(
      'ZtLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
