// Zero-Trust web kit. Starts the app with one change from Flutter's
// default: text in scripts the app has no font for (Hebrew, Arabic, emoji,
// and so on) is drawn with fonts served from this site, in fallback-fonts/,
// instead of being downloaded from Google Fonts on every visit. The page's
// security policy blocks other sites anyway; without this such text would
// show as empty boxes. tool/fetch_fallback_fonts.sh fills that folder
// after `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: new URL('fallback-fonts/', document.baseURI).href,
  },
});
