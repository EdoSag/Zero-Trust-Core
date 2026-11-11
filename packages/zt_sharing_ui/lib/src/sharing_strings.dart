import 'package:flutter/widgets.dart';

/// The sharing screens' text in English and Hebrew (the suite's languages),
/// picked from the app's current locale. [title] placeholders are what is
/// shared (a notebook, a list, a calendar), so no wording is app-specific.
class ZtSharingStrings {
  const ZtSharingStrings._(this._he);

  static const en = ZtSharingStrings._(false);
  static const he = ZtSharingStrings._(true);

  final bool _he;

  static ZtSharingStrings forLocale(Locale? locale) =>
      switch (locale?.languageCode) { 'he' || 'iw' => he, _ => en };

  static ZtSharingStrings of(BuildContext context) =>
      forLocale(Localizations.maybeLocaleOf(context));

  String _q(String title) => _he ? '״$title״' : '“$title”';

  String get sharingExplain => _he
      ? 'השיתוף מוצפן מקצה לקצה: רק האנשים שמשתפים איתם יכולים לקרוא. הם יראו את השם שתכתבו כאן.'
      : 'Sharing is end-to-end encrypted: only the people you share with can '
          'read it. They see the name you give here.';
  String get yourName => _he ? 'השם שלך' : 'Your name';
  String get yourNameHint =>
      _he ? 'איך האחרים יראו אותך' : 'How the others see you';
  String get nameRequired => _he ? 'צריך לכתוב שם' : 'Enter a name';
  String get continueLabel => _he ? 'המשך' : 'Continue';
  String get cancel => _he ? 'ביטול' : 'Cancel';
  String get later => _he ? 'אחר כך' : 'Later';
  String get done => _he ? 'סיום' : 'Done';
  String get needsInternet => _he
      ? 'אין חיבור לשרת. שיתוף צריך חיבור לאינטרנט.'
      : "Couldn't reach the server. Sharing needs an internet connection.";
  String get gone =>
      _he ? 'כבר לא חברת או חבר כאן.' : "You're no longer a member here.";
  String get waitingToJoin => _he ? 'ממתין לאישור' : 'Waiting to join';
  String get waitingExplain => _he
      ? 'הבעלים צריכים לאשר אותך. הראו להם את הקוד הזה; הוא צריך להיות זהה לקוד בטלפון שלהם.'
      : 'The owner has to let you in. Show them this code; it must match the '
          'one on their phone.';
  String get e2e => _he
      ? 'מוצפן מקצה לקצה. כל מי שכאן יכול להוסיף ולערוך; בעלים יכולים גם להזמין ולהסיר אנשים.'
      : 'End-to-end encrypted. Everyone here can add and edit; owners can also '
          'invite and remove people.';
  String people(int count) => _he
      ? (count == 1 ? 'אדם אחד' : '$count אנשים')
      : (count == 1 ? '1 person' : '$count people');
  String youName(String name) => _he ? '$name (את/ה)' : '$name (you)';
  String get owner => _he ? 'בעלים' : 'Owner';
  String get member => _he ? 'משתתף' : 'Member';
  String get makeOwner => _he ? 'הפיכה לבעלים' : 'Make owner';
  String get makeMember =>
      _he ? 'הפיכה למשתתף (לא בעלים)' : 'Make member (not owner)';
  String get remove => _he ? 'הסרה' : 'Remove';
  String removeQ(String name) => _he ? 'להסיר את $name?' : 'Remove $name?';
  String removeExplain(String title) => _he
      ? 'הגישה ל${_q(title)} תיחסם. ההצפנה עוברת למפתח חדש, כך שלא יוכלו לקרוא שום דבר שיתווסף מעכשיו.'
      : 'They lose access to ${_q(title)}. It moves to a new key, so they '
          "can't read anything added from now on.";
  String get invitePeople => _he ? 'הזמנת אנשים' : 'Invite people';
  String get leave => _he ? 'יציאה' : 'Leave';
  String leaveQ(String title) =>
      _he ? 'לצאת מ${_q(title)}?' : 'Leave ${_q(title)}?';
  String get leaveExplain => _he
      ? 'זה יוסר מהמכשירים שלך. האחרים ישמרו את זה.'
      : "It's removed from your devices. The others keep it.";
  String get deleteForEveryone => _he ? 'מחיקה לכולם' : 'Delete for everyone';
  String deleteQ(String title) => _he
      ? 'למחוק את ${_q(title)} לכולם?'
      : 'Delete ${_q(title)} for everyone?';
  String get deleteExplain => _he
      ? 'זה יימחק לכל המשתתפים, עם כל מה שבתוכו. אי אפשר לבטל את זה.'
      : "It's deleted for every member, with everything in it. This can't be "
          'undone.';
  String get syncNow => _he ? 'סנכרון עכשיו' : 'Sync now';
  String inviteTo(String title) =>
      _he ? 'הזמנה ל${_q(title)}' : 'Invite to ${_q(title)}';
  String inviteIntro(String app) => _he
      ? 'יוצרים הזמנה לאדם אחד. הוא סורק את קוד ה-QR, או פותח את הקישור ששלחתם, ב-$app. אחר כך משווים קוד קצר כדי לוודא שזה הוא.'
      : 'Make an invite for one person. They scan the QR code, or open the '
          'link you send them, in $app. Then you compare a short code to be '
          "sure it's them.";
  String get inviteAsOwner => _he ? 'הזמנה כבעלים' : 'Invite as an owner';
  String get inviteAsOwnerHint => _he
      ? 'בעלים יכולים להזמין ולהסיר אנשים'
      : 'Owners can invite and remove people';
  String get createInvite => _he ? 'יצירת הזמנה' : 'Create invite';
  String inviteReady(String app) => _he
      ? 'סרקו את הקוד בטלפון שלהם ב-$app, או שלחו להם את הקישור.'
      : 'Scan this code on their phone in $app, or send them the link.';
  String get inviteQr => _he ? 'קוד QR של ההזמנה' : 'Invite QR code';
  String get copyLink => _he ? 'העתקת קישור' : 'Copy link';
  String get linkCopied => _he ? 'הקישור הועתק' : 'Link copied';
  String get sendLink => _he ? 'שליחת קישור' : 'Send link';
  String inviteMessage(String title, String app, String link) => _he
      ? 'הצטרפו ל${_q(title)} ב-$app: $link'
      : 'Join ${_q(title)} in $app: $link';
  String get inviteNextSteps => _he
      ? 'ההזמנה עובדת פעם אחת, למשך 7 ימים. כשיענו, תראו אותם כאן: משווים את הקודים ומאשרים.'
      : 'The invite works once, for 7 days. When they answer, you see them '
          'here: compare the codes, then let them in.';
  String get checkForAnswers => _he ? 'בדיקת תשובות' : 'Check for answers';
  String joinRequest(String name) =>
      _he ? '$name רוצה להצטרף' : '$name wants to join';
  String joinRequestFor(String name, String title) => _he
      ? '$name רוצה להצטרף ל${_q(title)}'
      : '$name wants to join ${_q(title)}';
  String get joinRequestHint => _he
      ? 'הקישו כדי להשוות קודים ולאשר'
      : 'Tap to compare codes and let them in';
  String confirmJoinTitle(String name, String title) => _he
      ? 'לאשר ל-$name להצטרף ל${_q(title)}?'
      : 'Let $name into ${_q(title)}?';
  String get confirmJoinBody => _he
      ? 'בדקו שבטלפון שלהם מופיע אותו קוד. אם לא, ייתכן שמישהו אחר קיבל את ההזמנה.'
      : "Check that their phone shows this same code. If it doesn't, someone "
          'else may have the invite.';
  String get codesMatch => _he ? 'הקודים זהים' : 'Codes match';
  String get codesDiffer => _he ? 'הקודים שונים' : 'Codes differ';
  String joined(String name) => _he ? '$name הצטרף/ה' : '$name joined';
  String get joinTitle => _he ? 'הצטרפות עם הזמנה' : 'Join with an invite';
  String get joinIntro => _he
      ? 'הדביקו את קישור ההזמנה שקיבלתם, או סרקו את קוד ה-QR בטלפון השני.'
      : 'Paste the invite link you were sent, or scan the QR code on the other '
          'phone.';
  String get inviteLink => _he ? 'קישור ההזמנה' : 'Invite link';
  String get scanQr => _he ? 'סריקת קוד QR' : 'Scan QR code';
  String get inviteOtherApp => _he
      ? 'ההזמנה הזאת שייכת לאפליקציית Zero-Trust אחרת'
      : 'This invite is for another Zero-Trust app';
  String inviteInvalid(String app) =>
      _he ? 'זה לא קישור הזמנה של $app' : "That's not a $app invite link";
  String get inviteUsed => _he
      ? 'ההזמנה כבר שומשה, בוטלה או פגה. בקשו הזמנה חדשה.'
      : 'This invite was already used, withdrawn or has expired. Ask for a new '
          'one.';
  String get join => _he ? 'הצטרפות' : 'Join';
  String get joinCodeTitle => _he ? 'השוו את הקוד הזה' : 'Compare this code';
  String get joinCodeBody => _he
      ? 'גם בטלפון של הבעלים מופיע קוד. כשהקודים זהים, הם מאשרים אותך וזה יופיע אצלך.'
      : "The owner's phone shows a code too. When they match, the owner lets "
          'you in and it appears here.';
  String sharedWith(String names) =>
      _he ? 'משותף עם $names' : 'Shared with $names';
  String get peopleAndSharing => _he ? 'אנשים ושיתוף' : 'People and sharing';
}
