import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/zt_l10n.dart';
import 'zt_preferences.dart';

/// The languages every Zero-Trust app is written in, and the delegates an
/// app passes to `MaterialApp`.
///
/// ```dart
/// MaterialApp(
///   locale: ref.watch(ztLanguageProvider),
///   supportedLocales: ZtLanguages.supported,
///   localizationsDelegates: [AppL10n.delegate, ...ZtLanguages.delegates],
/// )
/// ```
///
/// Hebrew turns the whole app right-to-left: write layouts with
/// `EdgeInsetsDirectional`, `AlignmentDirectional` and `start`/`end`, never
/// `left`/`right`, so they flip with it.
abstract final class ZtLanguages {
  static const Locale english = Locale('en');
  static const Locale hebrew = Locale('he');

  /// English first: it is what a phone in any other language gets.
  static const List<Locale> supported = [english, hebrew];

  /// The core's strings plus Flutter's own (buttons, date pickers, text
  /// direction). Put the app's own delegate in front of these.
  static const List<LocalizationsDelegate<Object>> delegates = [
    ZtL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// A language's name in that language, as the picker shows it.
  static String nativeName(Locale locale) => switch (locale.languageCode) {
        'he' => 'עברית',
        _ => 'English',
      };
}

/// The language picked under Settings → Appearance → Language. English
/// until the user picks another; null means "follow the phone" (Hebrew on
/// a Hebrew phone, English on any other). Kept per install, like the theme.
class ZtLanguageController extends Notifier<Locale?> {
  static const String _key = 'language';
  static const String _phone = 'phone';

  /// What [preload] read, so the first frame is already in the right
  /// language. Absent until [preload] runs.
  static String? _preloaded;
  static bool _didPreload = false;

  bool _chosen = false;

  /// Reads the stored choice before `runApp`, so the app doesn't open in
  /// English and then switch. Optional: without it the choice applies a
  /// moment after start.
  static Future<void> preload([PreferencesStore? store]) async {
    try {
      _preloaded = await (store ?? SecurePreferencesStore()).read(_key);
    } on Object {
      _preloaded = null; // Unreadable: English.
    }
    _didPreload = true;
  }

  /// Forgets [preload]'s value (tests).
  @visibleForTesting
  static void resetPreload() {
    _preloaded = null;
    _didPreload = false;
  }

  static Locale? _decode(String? stored) {
    if (stored == _phone) return null;
    for (final locale in ZtLanguages.supported) {
      if (locale.languageCode == stored) return locale;
    }
    return ZtLanguages.english;
  }

  @override
  Locale? build() {
    if (_didPreload) return _decode(_preloaded);
    _load();
    return ZtLanguages.english;
  }

  Future<void> _load() async {
    final String? stored;
    try {
      stored = await ref.read(ztPreferencesStoreProvider).read(_key);
    } on Object {
      return; // Unreadable: keep English.
    }
    if (stored == null || _chosen) return;
    state = _decode(stored);
  }

  /// [locale] null follows the phone.
  Future<void> set(Locale? locale) async {
    _chosen = true;
    state = locale;
    final value = locale?.languageCode ?? _phone;
    _preloaded = value;
    await ref.read(ztPreferencesStoreProvider).write(_key, value);
  }
}

final ztLanguageProvider =
    NotifierProvider<ZtLanguageController, Locale?>(ZtLanguageController.new);
