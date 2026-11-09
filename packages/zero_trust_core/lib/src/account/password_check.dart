import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../l10n/zt_l10n.dart';

/// How hard a password is to guess, from 0 (trivial) to 4 (strong).
class PasswordStrength {
  const PasswordStrength(this.score, this.hint);

  final int score;

  /// One short tip for making it stronger, or null when it's strong.
  final String? hint;

  String get label => switch (score) {
        0 => ZtL10n.current.strengthVeryWeak,
        1 => ZtL10n.current.strengthWeak,
        2 => ZtL10n.current.strengthFair,
        3 => ZtL10n.current.strengthGood,
        _ => ZtL10n.current.strengthStrong,
      };

  /// What the core asks for in a new password.
  bool get acceptable => score >= 3;
}

/// Estimates [password]'s strength offline (nothing leaves the device).
///
/// Not a full zxcvbn: it rates length and variety, then marks down the
/// patterns guessers try first (common passwords, the email's name, repeats,
/// sequences like `1234` or `abcd`, keyboard rows), each counted as one
/// guessable token instead of its characters. The password protects the
/// data itself, so the bar is high: score 3 needs about 60 bits of entropy.
PasswordStrength estimatePasswordStrength(String password, {String? email}) {
  if (password.isEmpty) {
    return PasswordStrength(0, ZtL10n.current.enterAPassword);
  }
  var p = password.toLowerCase();
  final tips = <String>[];

  // Each guessable chunk is replaced by a single placeholder character,
  // worth one "word" instead of its full length.
  var tokens = 0;
  String strip(Pattern pattern, String tip) {
    final before = p;
    p = p.replaceAll(pattern, '\u0000');
    final found =
        '\u0000'.allMatches(p).length - '\u0000'.allMatches(before).length;
    if (found > 0) {
      tokens += found;
      tips.add(tip);
    }
    return p;
  }

  final local = email?.split('@').first.toLowerCase() ?? '';
  if (local.length >= 3) strip(local, ZtL10n.current.tipNoEmail);
  for (final word in _commonWords) {
    if (word.length >= 4 && p.contains(word)) {
      strip(word, ZtL10n.current.tipCommonWords);
    }
  }
  strip(RegExp(r'(.)\1{2,}'), ZtL10n.current.tipRepeated);
  for (final seq in _sequences) {
    for (var len = seq.length; len >= 4; len--) {
      for (var i = 0; i + len <= seq.length; i++) {
        final s = seq.substring(i, i + len);
        if (p.contains(s)) strip(s, ZtL10n.current.tipSequences);
        final r = s.split('').reversed.join();
        if (p.contains(r)) strip(r, ZtL10n.current.tipSequences);
      }
    }
  }
  strip(RegExp(r'(19|20)\d{2}'), ZtL10n.current.tipYears);

  final rest = p.replaceAll('\u0000', '');
  var pool = 0;
  if (RegExp('[a-z]').hasMatch(password)) pool += 26;
  if (RegExp('[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp('[0-9]').hasMatch(password)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) pool += 33;
  pool = max(pool, 10);
  // Remaining characters at the pool's entropy, plus ~11 bits per guessable
  // token (a dictionary of a couple of thousand entries).
  final bits = rest.runes.toSet().length < 3 && rest.isNotEmpty
      ? log(pool) / ln2 * 2 + tokens * 11
      : rest.length * log(pool) / ln2 + tokens * 11;

  final score = switch (bits) {
    < 28 => 0,
    < 40 => 1,
    < 60 => 2,
    < 80 => 3,
    _ => 4,
  };
  final hint = score >= 4
      ? null
      : tips.isNotEmpty
          ? tips.first
          : password.length < 16
              ? ZtL10n.current.tipLonger
              : ZtL10n.current.tipMix;
  return PasswordStrength(score, hint);
}

/// Checks a new password against Have I Been Pwned's list of passwords from
/// data breaches, without sending it: only the first 5 hex characters of
/// its SHA-1 hash go out (k-anonymity), and the matching is done here.
abstract interface class BreachedPasswordChecker {
  /// How many breaches the password appeared in (0 = none). Throws when the
  /// service can't be reached; callers then go ahead without the check.
  Future<int> timesSeen(String password);
}

class PwnedPasswordsChecker implements BreachedPasswordChecker {
  PwnedPasswordsChecker({http.Client? client, this.timeout = _timeout})
      : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 5);
  final http.Client _client;
  final Duration timeout;

  @override
  Future<int> timesSeen(String password) async {
    final hash = await Sha1().hash(utf8.encode(password));
    final hex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final prefix = hex.substring(0, 5);
    final suffix = hex.substring(5);
    final response = await _client.get(
      Uri.https('api.pwnedpasswords.com', '/range/$prefix'),
      // Padding hides how many suffixes share the prefix from onlookers.
      headers: const {'Add-Padding': 'true'},
    ).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    for (final line in const LineSplitter().convert(response.body)) {
      final i = line.indexOf(':');
      if (i == 35 && line.substring(0, i) == suffix) {
        // Padding rows carry a count of 0.
        return int.tryParse(line.substring(i + 1).trim()) ?? 0;
      }
    }
    return 0;
  }
}

/// Never finds a breach. For tests and for apps that turn the check off.
class NoBreachCheck implements BreachedPasswordChecker {
  const NoBreachCheck();
  @override
  Future<int> timesSeen(String password) async => 0;
}

final ztBreachedPasswordCheckerProvider =
    Provider<BreachedPasswordChecker>((ref) => PwnedPasswordsChecker());

/// The breached-password check for a new password: an error message when
/// it is known from a breach, else null. Offline or a slow service means no
/// check (null), never a blocked sign-up.
Future<String?> ztBreachedPasswordError(
    BreachedPasswordChecker checker, String password) async {
  final int seen;
  try {
    seen = await checker.timesSeen(password);
  } on Object {
    return null;
  }
  if (seen == 0) return null;
  return ZtL10n.current.passwordBreached;
}

/// Words and passwords guessers try first (lowercase). Short on purpose: it
/// only has to catch the obvious.
const _commonWords = [
  'password',
  'passw0rd',
  'p@ssword',
  'qwerty',
  'letmein',
  'welcome',
  'admin',
  'login',
  'iloveyou',
  'monkey',
  'dragon',
  'master',
  'shadow',
  'sunshine',
  'princess',
  'football',
  'baseball',
  'soccer',
  'superman',
  'batman',
  'trustno1',
  'secret',
  'freedom',
  'whatever',
  'starwars',
  'pokemon',
  'michael',
  'jennifer',
  'charlie',
  'jordan',
  'hunter',
  'summer',
  'winter',
  'spring',
  'autumn',
  'hello',
  'love',
  'google',
  'apple',
  'samsung',
  'facebook',
  'instagram',
  'zerotrust',
  'zero',
  'trust',
  'notes',
  'tasks',
  'fitness',
  'contacts',
  'changeme',
  'default',
  'computer',
  'internet',
  'killer',
  'pepper',
  'cookie',
  'ninja',
  'mustang',
  'access',
  'flower',
  'lovely',
  'family',
  'friends',
  'london',
  'israel',
];

const _sequences = [
  '0123456789',
  'abcdefghijklmnopqrstuvwxyz',
  'qwertyuiop',
  'asdfghjkl',
  'zxcvbnm',
  '1qaz2wsx3edc',
];
