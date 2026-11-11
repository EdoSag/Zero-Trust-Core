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
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL -o "$tmp" \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${VERSION}/sqlite3mc.wasm"
echo "${SHA256}  ${tmp}" | sha256sum -c --quiet -
mv "$tmp" "$out_dir/sqlite3mc.wasm"
trap - EXIT
echo "sqlite3mc.wasm ${VERSION} -> ${out_dir}/sqlite3mc.wasm"
