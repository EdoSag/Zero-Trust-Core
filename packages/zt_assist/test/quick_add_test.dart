import 'package:flutter_test/flutter_test.dart';
import 'package:zt_assist/zt_assist.dart';

void main() {
  // A Thursday.
  final now = DateTime(2026, 11, 26, 14, 30);

  ZtAssistQuickAdd? read(String answer, {String text = 'x 9'}) =>
      ZtAssistQuickAdd.fromAnswer(answer, text: text, now: now);

  group('a good answer', () {
    test('every field is read', () {
      const text = 'פגישה עם דנה ביום ראשון בארבע וחצי בקפה נחמה, שעה וחצי, '
          'להזכיר רבע שעה לפני';
      final result = read(
        '{"title":"פגישה עם דנה","date":"2026-11-29","time":"16:30",'
        '"minutes":90,"remind":15,"place":"קפה נחמה"}',
        text: text,
      )!;
      expect(result.title, 'פגישה עם דנה');
      expect(result.day, DateTime(2026, 11, 29));
      expect((result.hour, result.minute), (16, 30));
      expect(result.hasTime, isTrue);
      expect(result.lengthMinutes, 90);
      expect(result.remindMinutesBefore, 15);
      expect(result.place, 'קפה נחמה');
      expect(result.isEmpty, isFalse);
    });

    test('nulls stay empty', () {
      final result = read(
        '{"title":"Buy milk","date":null,"time":null,"minutes":null,'
        '"remind":null,"place":null}',
        text: 'Buy milk',
      )!;
      expect(result.title, 'Buy milk');
      expect(result.day, isNull);
      expect(result.hasTime, isFalse);
      expect(result.lengthMinutes, isNull);
      expect(result.remindMinutesBefore, isNull);
      expect(result.place, isNull);
    });

    test('a code block and words around it do not matter', () {
      final result = read(
        'Here is the JSON:\n```json\n{\n  "title": "Dentist",\n'
        '  "date": "2026-11-27",\n  "time": "09:00"\n}\n```\nNote: more',
      )!;
      expect(result.title, 'Dentist');
      expect(result.day, DateTime(2026, 11, 27));
      expect((result.hour, result.minute), (9, 0));
    });

    test('only the first object counts', () {
      final result = read(
        '{"title":"First {one}","date":null}\n{"title":"Second"}',
      )!;
      expect(result.title, 'First {one}');
    });

    test('"null" and "none" in quotes mean nothing', () {
      final result = read(
        '{"title":"Call Dad","date":"null","time":"None","place":"n/a"}',
      )!;
      expect(result.day, isNull);
      expect(result.hasTime, isFalse);
      expect(result.place, isNull);
    });

    test('numbers written as text are read', () {
      final result = read('{"title":"Run","minutes":"45","remind":"10"}')!;
      expect(result.lengthMinutes, 45);
      expect(result.remindMinutesBefore, 10);
    });

    test('a time with am or pm is read', () {
      expect(read('{"time":"9:30 pm"}')!.hour, 21);
      expect(read('{"time":"12:05 AM"}')!.hour, 0);
      expect(read('{"time":"07:15:00"}')!.minute, 15);
    });

    test('a date that also carries a time keeps its day', () {
      expect(
        read('{"date":"2026-12-01T10:00"}')!.day,
        DateTime(2026, 12, 1),
      );
    });

    test('a very long title is cut', () {
      final result = read('{"title":"${'a' * 400}"}')!;
      expect(result.title!.length, 200);
    });
  });

  group('what is not trusted', () {
    test('a day that does not exist', () {
      expect(read('{"title":"x","date":"2026-11-31"}')!.day, isNull);
      expect(read('{"title":"x","date":"2026-13-01"}')!.day, isNull);
      expect(read('{"title":"x","date":"tomorrow"}')!.day, isNull);
      expect(read('{"title":"x","date":"27/11/2026"}')!.day, isNull);
    });

    test('a day in the past, or too far ahead', () {
      expect(read('{"title":"x","date":"2026-11-25"}')!.day, isNull);
      expect(read('{"title":"x","date":"2032-01-01"}')!.day, isNull);
      // Today itself is fine.
      expect(
        read('{"title":"x","date":"2026-11-26"}')!.day,
        DateTime(2026, 11, 26),
      );
    });

    test('a time that is not one', () {
      expect(read('{"title":"x","time":"25:00"}')!.hasTime, isFalse);
      expect(read('{"title":"x","time":"10:75"}')!.hasTime, isFalse);
      expect(read('{"title":"x","time":"13:00 pm"}')!.hasTime, isFalse);
      expect(read('{"title":"x","time":"morning"}')!.hasTime, isFalse);
      expect(read('{"title":"x","time":9}')!.hasTime, isFalse);
    });

    test('a time the line gives no reason for', () {
      expect(
        read('{"title":"Buy milk","time":"09:00"}', text: 'Buy milk tomorrow')!
            .hasTime,
        isFalse,
      );
      // Words are a reason too, in both languages.
      expect(
        read('{"time":"21:00"}', text: 'Call mum in the evening')!.hour,
        21,
      );
      expect(read('{"time":"16:30"}', text: 'פגישה בארבע וחצי')!.hour, 16);
    });

    test('a length or a reminder out of range', () {
      final result = read(
        '{"title":"x","minutes":2,"remind":-5}',
      )!;
      expect(result.lengthMinutes, isNull);
      expect(result.remindMinutesBefore, isNull);
      expect(read('{"title":"x","minutes":999999}')!.lengthMinutes, isNull);
      expect(read('{"title":"x","remind":0}')!.remindMinutesBefore, 0);
    });

    test('a place the line does not name', () {
      expect(
        read(
          '{"title":"Lunch","place":"Cafe Nehama"}',
          text: 'Lunch with Dana on Friday',
        )!
            .place,
        isNull,
      );
      // Case and spacing do not count.
      expect(
        read(
          '{"title":"Lunch","place":"cafe  nehama"}',
          text: 'Lunch at Cafe Nehama on Friday',
        )!
            .place,
        'cafe nehama',
      );
    });

    test('an answer that is not the JSON asked for', () {
      expect(read('I could not read that.'), isNull);
      expect(read('{"title": "Dentist", "date": '), isNull);
      expect(read('{title: Dentist}'), isNull);
      expect(read('["Dentist"]'), isNull);
      expect(read(''), isNull);
    });

    test('an answer with nothing in it', () {
      expect(read('{}'), isNull);
      expect(read('{"title":"","date":null,"time":"99:99"}'), isNull);
      expect(read('{"title":42}'), isNull);
    });
  });
}
