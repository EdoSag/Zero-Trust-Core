import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  group('estimatePasswordStrength', () {
    int score(String p, {String? email}) =>
        estimatePasswordStrength(p, email: email).score;

    test('common patterns rate low', () {
      for (final p in [
        'password',
        'Password123!',
        'qwerty123456',
        'Summer2024!',
        'aaaaaaaaaaaaaaaa',
        'abcd1234abcd',
      ]) {
        expect(score(p), lessThan(3), reason: p);
        expect(estimatePasswordStrength(p).acceptable, isFalse, reason: p);
      }
    });

    test('the email name counts as one guess', () {
      expect(
          score('edosagron2025', email: 'edosagron@example.com'), lessThan(3));
      expect(
          estimatePasswordStrength('edosagron2025',
                  email: 'edosagron@example.com')
              .hint,
          'Don\'t use your email in it.');
    });

    test('long passphrases and random strings rate high', () {
      for (final p in [
        'correct horse battery',
        'ocean-maple-rocket-violin',
        'Xk9#mQ2vL7pR',
        'tY8qWz3nB5vKc',
      ]) {
        expect(score(p), greaterThanOrEqualTo(3), reason: p);
      }
    });

    test('the validator for new passwords needs length and strength', () {
      expect(ztValidateNewPassword('short'), 'Use at least 12 characters.');
      expect(ztValidateNewPassword('password1234'), startsWith('Too easy'));
      expect(ztValidateNewPassword('ocean-maple-rocket-violin'), isNull);
    });
  });

  group('PwnedPasswordsChecker', () {
    // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
    test('sends only the 5-character prefix and matches locally', () async {
      final requests = <http.Request>[];
      final checker = PwnedPasswordsChecker(client: MockClient((r) async {
        requests.add(r);
        return http.Response(
            '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n'
            '1E4C9B93F3F0682250B6CF8331B7EE68FD8:9659365\r\n'
            '011053FD0102E94D6AE2F8B83D76FAF94F6:0',
            200);
      }));
      expect(await checker.timesSeen('password'), 9659365);
      expect(requests.single.url.path, '/range/5BAA6');
      expect(requests.single.headers['Add-Padding'], 'true');
      // Neither the password nor the rest of its hash leaves the device.
      expect(requests.single.url.query, isEmpty);
      expect(requests.single.url.toString(),
          isNot(contains('1E4C9B93F3F0682250B6CF8331B7EE68FD8')));
      expect(requests.single.body, isEmpty);
    });

    test('not in the list: 0; padding rows (count 0) are not matches',
        () async {
      final checker = PwnedPasswordsChecker(
          client: MockClient((_) async =>
              http.Response('1E4C9B93F3F0682250B6CF8331B7EE68FD8:0', 200)));
      expect(await checker.timesSeen('password'), 0);
      expect(await checker.timesSeen('something else entirely'), 0);
    });

    test('offline or a server error never blocks the user', () async {
      final down = PwnedPasswordsChecker(
          client: MockClient((_) async => http.Response('', 503)));
      expect(await ztBreachedPasswordError(down, 'password'), isNull);
      final offline = PwnedPasswordsChecker(
          client: MockClient((_) => throw http.ClientException('offline')));
      expect(await ztBreachedPasswordError(offline, 'password'), isNull);
    });
  });
}
