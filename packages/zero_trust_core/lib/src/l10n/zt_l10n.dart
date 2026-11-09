import 'package:flutter/widgets.dart';

import 'generated/zt_localizations.dart';

export 'generated/zt_localizations.dart';

/// The core's own strings (sign-in, unlock, settings, errors), from the ARB
/// files in `lib/l10n/`. English is built in; add a language by adding
/// `zt_<code>.arb` and running `flutter gen-l10n` in this package.
///
/// Apps add [delegate] to `MaterialApp.localizationsDelegates`. Without it,
/// or for a language the core doesn't have yet, everything stays English.
abstract final class ZtL10n {
  /// The strings for the app's current language, for code without a
  /// [BuildContext] (error messages, validators). English until [delegate]
  /// loads another language.
  static ZtLocalizations current = lookupZtLocalizations(const Locale('en'));

  static const LocalizationsDelegate<ZtLocalizations> delegate =
      _ZtL10nDelegate();

  static const List<Locale> supportedLocales = ZtLocalizations.supportedLocales;

  /// The strings for [context]'s language, falling back to [current].
  static ZtLocalizations of(BuildContext context) =>
      ZtLocalizations.of(context) ?? current;
}

class _ZtL10nDelegate extends LocalizationsDelegate<ZtLocalizations> {
  const _ZtL10nDelegate();

  /// Every language: one the core doesn't have yet gets English, rather
  /// than Flutter warning that the app's language isn't supported.
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<ZtLocalizations> load(Locale locale) async {
    final strings = await ZtLocalizations.delegate.load(
        ZtLocalizations.delegate.isSupported(locale)
            ? locale
            : const Locale('en'));
    ZtL10n.current = strings;
    return strings;
  }

  @override
  bool shouldReload(_ZtL10nDelegate old) => false;
}
