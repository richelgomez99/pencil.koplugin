#!/usr/bin/env bash
# Install pencil.koplugin into KOReader on an Android device (Boox) over adb.
# Usage: ./install-android.sh [adb-serial-or-host:port]
# Requires KOReader v2026.07 or newer (the stylus callback API landed 2026-07-11).
set -euo pipefail
ADB="$HOME/Android/Sdk/platform-tools/adb"
HERE="$(cd "$(dirname "$0")" && pwd)"
T=${1:-}
A() { if [ -n "$T" ]; then "$ADB" -s "$T" "$@"; else "$ADB" "$@"; fi; }
echo "== KOReader version on device"
A shell dumpsys package org.koreader.launcher 2>/dev/null | grep -m1 versionName || { echo "KOReader not found"; exit 1; }
DATA=/sdcard/koreader
A shell test -d "$DATA" || { echo "$DATA missing: open KOReader once first"; exit 1; }
echo "== pushing plugin to $DATA/plugins/pencil.koplugin"
A shell mkdir -p "$DATA/plugins"
A shell rm -rf "$DATA/plugins/pencil.koplugin"
A push "$HERE/pencil.koplugin" "$DATA/plugins/pencil.koplugin" >/dev/null
A shell ls -la "$DATA/plugins/pencil.koplugin"
echo "== done. Restart KOReader, then: top menu > More tools > Pencil > Enabled"
echo "   KOReader's log: $DATA/crash.log (grep Pencil)"
