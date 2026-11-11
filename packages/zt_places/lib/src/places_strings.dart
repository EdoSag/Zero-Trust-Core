import 'package:flutter/widgets.dart';

/// The place screens' text in English and Hebrew (the suite's languages).
/// Picked from the app's current locale; anything else gets English.
class ZtPlacesStrings {
  const ZtPlacesStrings._(this._he);

  static const en = ZtPlacesStrings._(false);
  static const he = ZtPlacesStrings._(true);

  final bool _he;

  static ZtPlacesStrings forLocale(Locale? locale) =>
      switch (locale?.languageCode) { 'he' || 'iw' => he, _ => en };

  static ZtPlacesStrings of(BuildContext context) =>
      forLocale(Localizations.maybeLocaleOf(context));

  String get title => _he ? 'תזכורת לפי מיקום' : 'Location reminder';
  String get whenArrive => _he ? 'כשאגיע' : 'When I arrive';
  String get whenLeave => _he ? 'כשאצא' : 'When I leave';
  String get myPlaces => _he ? 'המקומות שלי' : 'My places';
  String get useCurrent =>
      _he ? 'השתמש במיקום הנוכחי שלי' : 'Use my current location';
  String get locating => _he ? 'מאתר את המיקום שלך…' : 'Finding your location…';
  String get locationFailed => _he
      ? 'לא הצלחנו לאתר את המיקום. בדוק שהמיקום מופעל ונסה שוב.'
      : "Couldn't get your location. Check that location is on and try again.";
  String get pasteLabel => _he
      ? 'או הדבק קואורדינטות או קישור למפה'
      : 'Or paste coordinates or a map link';
  String get pasteInvalid => _he
      ? 'לא נמצא מיקום בטקסט. אי אפשר לחפש כתובת בלי לשלוח אותה לשרת, לכן הדבק קישור למפה או קואורדינטות.'
      : "No location found in this text. Addresses can't be looked up without "
          'sending them to a server, so paste a map link or coordinates.';
  String get placeName => _he ? 'שם המקום' : 'Place name';
  String get placeNameHint =>
      _he ? 'למשל בית, משרד, סופר' : 'For example Home, Office, Supermarket';
  String get radius => _he ? 'רדיוס' : 'Radius';
  String distance(double meters) => meters >= 1000
      ? (_he ? '${_trim(meters / 1000)} ק״מ' : '${_trim(meters / 1000)} km')
      : (_he ? '${meters.round()} מ׳' : '${meters.round()} m');
  String get saveToPlaces => _he ? 'שמור במקומות שלי' : 'Save to my places';
  String get privacy => _he
      ? 'המיקום שלך נשאר בטלפון. הטלפון עצמו מזהה את המקום, ושום דבר לא נשלח אלינו או לגוגל.'
      : 'Your location stays on this phone. The phone itself watches for the '
          'place; nothing is sent to us or to Google.';
  String get needsPermission => _he
      ? 'כדי להזכיר גם כשהאפליקציה סגורה, אפשר גישה למיקום מדויק "כל הזמן" ולהתראות.'
      : 'To remind you while the app is closed, allow precise location '
          '"All the time" and notifications.';
  String get allow => _he ? 'אפשר' : 'Allow';
  String get openSettings => _he ? 'פתח הגדרות' : 'Open settings';
  String get locationOff => _he
      ? 'המיקום כבוי בטלפון. הפעל אותו כדי לקבל תזכורות לפי מיקום.'
      : 'Location is off on this phone. Turn it on to get place reminders.';
  String get done => _he ? 'סיום' : 'Done';
  String get choosePlace => _he ? 'בחר מקום קודם' : 'Choose a place first';
  String get nameNeeded => _he ? 'תן שם למקום' : 'Give the place a name';
  String get removePlace => _he ? 'הסר מהמקומות שלי' : 'Remove from my places';
  String get unsupported => _he
      ? 'תזכורות לפי מיקום זמינות כרגע רק באנדרואיד.'
      : 'Location reminders work on Android for now.';
  String arriving(String place) =>
      _he ? 'בהגעה אל $place' : 'When you arrive at $place';
  String leaving(String place) =>
      _he ? 'ביציאה מ־$place' : 'When you leave $place';
  String get channelName => _he ? 'תזכורות לפי מיקום' : 'Place reminders';
  String get channelDescription => _he
      ? 'תזכורות כשמגיעים למקום או יוצאים ממנו'
      : 'Reminders when you arrive at or leave a place';
  String get publicTitle => _he ? 'תזכורת לפי מיקום' : 'Place reminder';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
