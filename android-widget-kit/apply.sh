#!/usr/bin/env bash
# Copies the Zero-Trust widget kit into an app and sets the app's accent.
#
#   android-widget-kit/apply.sh <path to app repo> <accent hex, e.g. #06B6D4>
#
# Safe to run again: it overwrites the kit's own files (all named zt_widget_*
# or ic_zt_widget_*) and nothing else.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="${1:?app repo path}"
accent="${2:?accent colour, e.g. #06B6D4}"
res="$app/android/app/src/main/res"
[ -d "$res" ] || { echo "No $res" >&2; exit 1; }
cp -R "$here/res/." "$res/"
cat > "$res/values/zt_widget_accent.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<!-- This app's accent for the Zero-Trust widget kit (same as ZtAppConfig.accent). -->
<resources>
    <color name="zt_widget_accent">$accent</color>
</resources>
XML
echo "Widget kit copied into $res (accent $accent)"
