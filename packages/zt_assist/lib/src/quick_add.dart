import 'dart:convert';

/// What ZT Assist read from a typed line like "dentist tomorrow at 9,
/// remind me an hour before": the answer to a `ZtAssistTask.quickAdd`
/// request, checked.
///
/// A small model gets things wrong, so nothing here is taken on trust: a
/// day that is not a real day, a time the line gives no reason for and a
/// place the line does not name are dropped. A dropped field is null, and
/// the asking app fills it from its own reading of the line.
///
/// How an app puts the two readings together:
///  * the day: the app's own reading where it found one (it counts days
///    exactly), else [day];
///  * the title, the time, the length, the reminder and the place: from
///    here where there is one (the model understands "half past four in
///    the afternoon"), else the app's own.
///
/// The result is shown to the user before anything is saved.
class ZtAssistQuickAdd {
  const ZtAssistQuickAdd({
    this.title,
    this.day,
    this.hour,
    this.minute,
    this.lengthMinutes,
    this.remindMinutesBefore,
    this.place,
  }) : assert((hour == null) == (minute == null));

  /// What to do, or what happens, without the day, time and place.
  final String? title;

  /// The day, at midnight, local time.
  final DateTime? day;

  /// The time of day; both set or both null.
  final int? hour;
  final int? minute;

  /// How long it takes.
  final int? lengthMinutes;

  /// How long before it the user wants a reminder.
  final int? remindMinutesBefore;

  /// Where it is, in the line's own words.
  final String? place;

  bool get hasTime => hour != null;

  /// Nothing usable was read.
  bool get isEmpty =>
      title == null &&
      day == null &&
      hour == null &&
      lengthMinutes == null &&
      remindMinutesBefore == null &&
      place == null;

  /// The longest line worth sending. ZT Assist reads no more of it.
  static const int maxTextLength = 500;

  /// Reads ZT Assist's [answer] to the line [text], asked at [now].
  ///
  /// Null when the answer is not the JSON it was asked for, or nothing in
  /// it stood up to the checks.
  static ZtAssistQuickAdd? fromAnswer(
    String answer, {
    required String text,
    required DateTime now,
  }) {
    final fields = _object(answer);
    if (fields == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final time = _time(fields['time'], text);
    final read = ZtAssistQuickAdd(
      title: _title(fields['title']),
      day: _day(fields['date'], today),
      hour: time?.$1,
      minute: time?.$2,
      lengthMinutes: _number(fields['minutes'], least: 5, most: 7 * 24 * 60),
      remindMinutesBefore: _number(
        fields['remind'],
        least: 0,
        most: 28 * 24 * 60,
      ),
      place: _place(fields['place'], text),
    );
    return read.isEmpty ? null : read;
  }

  /// The first JSON object in [answer]: models like to wrap it in a code
  /// block or to add a word before it.
  static Map<String, Object?>? _object(String answer) {
    final start = answer.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < answer.length; i++) {
      final unit = answer.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5C) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
        }
        continue;
      }
      if (unit == 0x22) {
        inString = true;
      } else if (unit == 0x7B) {
        depth++;
      } else if (unit == 0x7D) {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(answer.substring(start, i + 1));
            return decoded is Map<String, Object?> ? decoded : null;
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// "null", "none" and the like, which a model writes inside quotes.
  static bool _nothing(String value) => const {
        '',
        'null',
        'none',
        'n/a',
        '-',
      }.contains(value.toLowerCase());

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _nothing(text) ? null : text;
  }

  static String? _title(Object? value) {
    final title = _text(value);
    if (title == null) return null;
    final runes = title.runes;
    return runes.length <= 200
        ? title
        : String.fromCharCodes(runes.take(200)).trim();
  }

  static DateTime? _day(Object? value, DateTime today) {
    final text = _text(value);
    if (text == null) return null;
    // "2026-11-27", and "2026-11-27T09:00" from a model that says too much.
    final match =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final dayOfMonth = int.parse(match.group(3)!);
    final day = DateTime(year, month, dayOfMonth);
    // 31 November rolls over to December: not a day the line named.
    if (day.year != year || day.month != month || day.day != dayOfMonth) {
      return null;
    }
    // Something to do is not in the past, and a small model's far future
    // is a slip more often than a plan.
    if (day.isBefore(today)) return null;
    if (day.isAfter(DateTime(today.year + 5, today.month, today.day))) {
      return null;
    }
    return day;
  }

  // What a line that names a time of day has in it, other than a digit.
  static const _timeWords = [
    // English.
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'noon', 'midday', 'midnight', 'morning',
    'afternoon', 'evening', 'night', "o'clock", 'half past', 'quarter',
    // Hebrew.
    'אחת', 'שתיים', 'שתים', 'שלוש', 'ארבע', 'חמש', 'שש', 'שבע', 'שמונה',
    'תשע', 'עשר', 'בוקר', 'צהריים', 'צהרים', 'ערב', 'לילה', 'חצות', 'וחצי',
    'ורבע',
  ];

  static (int, int)? _time(Object? value, String text) {
    final answer = _text(value);
    if (answer == null) return null;
    final match = RegExp(
      r'^(\d{1,2})[:.](\d{2})(?::\d{2})?\s*(am|pm)?$',
      caseSensitive: false,
    ).firstMatch(answer);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final half = match.group(3)?.toLowerCase();
    if (half != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (half == 'pm' ? 12 : 0);
    }
    if (hour > 23 || minute > 59) return null;
    // A time the line gives no reason for was made up.
    final line = text.toLowerCase();
    final named = RegExp(r'\d').hasMatch(line) || _timeWords.any(line.contains);
    return named ? (hour, minute) : null;
  }

  static int? _number(Object? value, {required int least, required int most}) {
    final number = switch (value) {
      final num n => n,
      final String s => num.tryParse(s.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite) return null;
    final whole = number.round();
    return whole < least || whole > most ? null : whole;
  }

  static String _plain(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? _place(Object? value, String text) {
    final place = _text(value);
    if (place == null || place.runes.length > 120) return null;
    // A place is copied from the line, never worked out: one the line does
    // not have was made up.
    return _plain(text).contains(_plain(place)) ? place : null;
  }
}
