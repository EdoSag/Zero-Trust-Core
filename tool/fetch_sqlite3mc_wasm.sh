#!/usr/bin/env bash
# Downloads the encrypted SQLite (SQLite3 Multiple Ciphers, WebAssembly) that
# a Zero-Trust web build loads, and checks it against a pinned checksum.
#
# Usage, from an app repository: path/to/fetch_sqlite3mc_wasm.sh web/
#
# The version must match the `sqlite3` package in the app's pubspec.lock.
# When that package is upgraded, update both lines below (the release page
# is https://github.com/simolus3/sqlite3.dart/releases).
set -euo pipefail

VERSION="3.9.1"
SHA256="408a1d9bf8071bfb6e91aba005e6c8e2072c240784e1d199bbd7eb441dd5ea94"

out_dir="${1:-web}"
mkdir -p "$out_dir"

# The WebAssembly file and the Dart package call into each other: a
# different version fails when the browser loads it ("LinkError ... function
# import requires a callable") and the app then never opens its store. Stop
# the build instead.
lock="$(cd "$out_dir/.." && pwd)/pubspec.lock"
if [ -f "$lock" ]; then
  locked="$(awk '/^  sqlite3:$/{f=1} f && /version:/{gsub(/[" ]/,"",$0); sub(/version:/,"",$0); print; exit}' "$lock")"
  if [ -n "$locked" ] && [ "$locked" != "$VERSION" ]; then
    echo "sqlite3 is $locked in $lock, but the pinned sqlite3mc.wasm is $VERSION." >&2
    echo "Run: flutter pub upgrade sqlite3   (or update VERSION and SHA256 in $0)" >&2
    exit 1
  fi
fi
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL -o "$tmp" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${VERSION}/sqlite3mc.wasm"
echo "${SHA256}  ${tmp}" | sha256sum -c --quiet -
mv "$tmp" "$out_dir/sqlite3mc.wasm"
trap - EXIT
echo "sqlite3mc.wasm ${VERSION} -> ${out_dir}/sqlite3mc.wasm"
