#!/usr/bin/env bash
# Writes the Zero-Trust web kit into an app's web/ folder: index.html with
# the security policy and loading screen, manifest.json, zt_boot.js,
# flutter_bootstrap.js (fonts from this site, not Google), a _headers file, and the pinned encrypted-SQLite WebAssembly file.
#
#   tool/apply_web_kit.sh <app>/web \
#     --name "Zero-Trust Notes" --short-name "ZT Notes" \
#     --description "Private notes, encrypted in your browser." \
#     --theme-color "#F59E0B" \
#     --supabase-url "https://abcd.supabase.co"
#
# Optional: --connect "https://tiles.example"  extra hosts the app may call
#           --img "https://tiles.example"      extra hosts images may load from
#           --no-wasm                          skip fetching sqlite3mc.wasm
#
# After `flutter build web --no-web-resources-cdn`, run
# tool/fetch_fallback_fonts.sh build/web so Hebrew, emoji and other scripts
# draw without calling Google Fonts.
#
# Run it again after the kit changes; it overwrites only the files it owns.
# Icons (favicon.png, icons/) stay the app's own.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
kit="$here/../web-kit"

dest="${1:-}"
[ -n "$dest" ] || { echo "usage: $0 <app web dir> --name ... (see the header)" >&2; exit 2; }
shift

name="" short="" description="" color="#2563EB" supabase="" connect="" img="" wasm=1
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --short-name) short="$2"; shift 2 ;;
    --description) description="$2"; shift 2 ;;
    --theme-color) color="$2"; shift 2 ;;
    --supabase-url) supabase="$2"; shift 2 ;;
    --connect) connect="$2"; shift 2 ;;
    --img) img="$2"; shift 2 ;;
    --no-wasm) wasm=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$name" ] || { echo "--name is required" >&2; exit 2; }
[ -n "$supabase" ] || { echo "--supabase-url is required" >&2; exit 2; }
short="${short:-$name}"
description="${description:-$name}"

case "$supabase" in
  https://*) ;;
  *) echo "--supabase-url must start with https://" >&2; exit 2 ;;
esac
host="${supabase#https://}"; host="${host%%/*}"
# The policy sits in an HTML attribute and a JSON string: keep values plain.
for v in "$name" "$short" "$description" "$color" "$host" "$connect" "$img"; do
  case "$v" in
    *[\"\'\<\>\;\&\\]*|*$'\n'*) echo "unsupported character in: $v" >&2; exit 2 ;;
  esac
done

connect_src="https://$host wss://$host${connect:+ $connect}"
img_src="${img:+ $img}"

render() {
  ZT_NAME="$name" ZT_SHORT="$short" ZT_DESC="$description" ZT_COLOR="$color" \
  ZT_CONNECT="$connect_src" ZT_IMG="$img_src" python3 - "$1" "$2" <<'PY'
import os, sys
text = open(sys.argv[1], encoding="utf-8").read()
for token, env in (("@ZT_NAME@", "ZT_NAME"), ("@ZT_SHORT_NAME@", "ZT_SHORT"),
                   ("@ZT_DESCRIPTION@", "ZT_DESC"), ("@ZT_THEME_COLOR@", "ZT_COLOR"),
                   ("@ZT_CONNECT@", "ZT_CONNECT"), ("@ZT_IMG@", "ZT_IMG")):
    text = text.replace(token, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(text)
PY
}

mkdir -p "$dest"
render "$kit/index.html.tmpl" "$dest/index.html"
render "$kit/manifest.json.tmpl" "$dest/manifest.json"
cp "$kit/zt_boot.js" "$dest/zt_boot.js"
cp "$kit/flutter_bootstrap.js" "$dest/flutter_bootstrap.js"
cp "$kit/_headers.tmpl" "$dest/_headers"
if [ "$wasm" = 1 ]; then "$here/fetch_sqlite3mc_wasm.sh" "$dest/"; fi
echo "Web kit written to $dest"
