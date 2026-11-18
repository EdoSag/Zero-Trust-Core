#!/usr/bin/env bash
# Copies the fonts Flutter falls back to (Noto, for scripts and emoji the
# app's own font lacks) into a built web app, so the browser gets them from
# the app's own site and never from Google Fonts.
#
#   flutter build web --no-web-resources-cdn
#   tool/fetch_fallback_fonts.sh build/web
#
# The list is read from the build itself, so it always matches the Flutter
# version that made it. Chinese, Japanese and Korean fonts are large
# (tens of MB) and skipped unless you pass --with-cjk.
set -euo pipefail

build="${1:-}"
[ -f "$build/main.dart.js" ] || { echo "usage: $0 <build/web> [--with-cjk]" >&2; exit 2; }
cjk=0; [ "${2:-}" = "--with-cjk" ] && cjk=1

out="$build/fallback-fonts"
mkdir -p "$out"
list="$(mktemp)"
trap 'rm -f "$list"' EXIT
grep -oE '"[a-z0-9]+/v[0-9]+/[A-Za-z0-9_.-]+\.(woff2|ttf)"' "$build/main.dart.js" \
  | tr -d '"' | sort -u > "$list"
if [ "$cjk" = 0 ]; then
  grep -vE '^notosans(sc|tc|hk|jp|kr)/' "$list" > "$list.keep" && mv "$list.keep" "$list"
fi
[ -s "$list" ] || { echo "no fallback fonts found in $build/main.dart.js" >&2; exit 1; }

fetch() {
  local path="$1" out="$2" dest
  # Paths come from the build; refuse anything that could leave the folder.
  case "$path" in *..*|/*) echo "bad font path: $path" >&2; return 1 ;; esac
  dest="$out/$path"
  [ -s "$dest" ] && return 0
  mkdir -p "$(dirname "$dest")"
  curl -fsSL --retry 4 --retry-delay 2 -o "$dest.part" "https://fonts.gstatic.com/s/$path"
  mv "$dest.part" "$dest"
}
export -f fetch
xargs -P 8 -I{} bash -c 'fetch "$1" "$2"' _ {} "$out" < "$list"

echo "$(wc -l < "$list" | tr -d ' ') fallback fonts in $out ($(du -sh "$out" | cut -f1))"
