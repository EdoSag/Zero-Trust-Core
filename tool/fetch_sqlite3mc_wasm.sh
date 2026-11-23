#!/usr/bin/env bash
# Downloads the encrypted SQLite (SQLite3 Multiple Ciphers, WebAssembly) that
# a Zero-Trust web build loads, and checks it against a pinned checksum.
#
# Usage, from an app repository: path/to/fetch_sqlite3mc_wasm.sh web/
#
# The version follows the `sqlite3` package in the app's pubspec.lock (the
# newest known one when there is no lock yet). Each version's file is
# checked against its pinned checksum below; when the package is upgraded
# to a version not listed, add it (the release page is
# https://github.com/simolus3/sqlite3.dart/releases).
set -euo pipefail

LATEST="3.9.2"
sha256_for() {
  case "$1" in
    3.9.1) echo "408a1d9bf8071bfb6e91aba005e6c8e2072c240784e1d199bbd7eb441dd5ea94" ;;
    3.9.2) echo "92f4d05a91b3a89b6d68720cd16c46c1a455c23f4a5c2e447259ed84c168bb2f" ;;
    *) echo "" ;;
  esac
}

out_dir="${1:-web}"
mkdir -p "$out_dir"

# The WebAssembly file and the Dart package call into each other: a
# different version fails when the browser loads it ("LinkError ... function
# import requires a callable") and the app then never opens its store. So
# the file always matches the locked package, or the build stops.
VERSION="$LATEST"
lock="$(cd "$out_dir/.." && pwd)/pubspec.lock"
if [ -f "$lock" ]; then
  locked="$(awk '/^  sqlite3:$/{f=1} f && /version:/{gsub(/[" ]/,"",$0); sub(/version:/,"",$0); print; exit}' "$lock")"
  if [ -n "$locked" ]; then VERSION="$locked"; fi
fi
SHA256="$(sha256_for "$VERSION")"
if [ -z "$SHA256" ]; then
  echo "sqlite3 is $VERSION in $lock, but $0 has no checksum for its sqlite3mc.wasm." >&2
  echo "Add the version and the SHA-256 of its sqlite3mc.wasm to sha256_for in $0." >&2
  exit 1
fi
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL -o "$tmp" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${VERSION}/sqlite3mc.wasm"
echo "${SHA256}  ${tmp}" | sha256sum -c --quiet -
mv "$tmp" "$out_dir/sqlite3mc.wasm"
trap - EXIT
echo "sqlite3mc.wasm ${VERSION} -> ${out_dir}/sqlite3mc.wasm"
