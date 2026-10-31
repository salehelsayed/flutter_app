#!/bin/bash
# Share one Thought from a disposable emulator on Orbit: open composer, attach photos (optional), type caption, Share.
#   orbit_fill_post.sh <serial> <caption> [photo-file-name ...]
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; C="$2"; shift 2; D="$(dirname "$0")"
# The Unicode IME must be active BEFORE the caption field takes focus, or the field keeps the old IME.
adb -s "$S" shell ime enable io.appium.settings/.UnicodeIME >/dev/null; adb -s "$S" shell ime set io.appium.settings/.UnicodeIME >/dev/null
# Orbit with an own thought never idles (dump fails): then tap the + by the own face.
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Share a thought"' || adb -s "$S" shell input tap 587 1282
sleep 4
if [ $# -gt 0 ]; then
  bash "$D/setA_ui.sh" tap "$S" 'content-desc="Media"' || exit 3
  sleep 4
  bash "$D/orbit_fill_pick.sh" "$S" "$@" || exit 4
  sleep 5
fi
bash "$D/setA_ui.sh" tap "$S" 'android.widget.EditText' || exit 5
sleep 1.5
python3 "$D/orbit_fill_type.py" "$S" "$C"
sleep 2
adb -s "$S" shell "rm -f /sdcard/u.xml; uiautomator dump /sdcard/u.xml >/dev/null; cat /sdcard/u.xml" | tr '>' '\n' | grep EditText | grep -o 'text="[^"]*"'
echo "photos attached: $(adb -s "$S" shell cat /sdcard/u.xml | tr '>' '\n' | grep -c 'content-desc="Delete"')"
[ -n "$SHOT" ] && bash "$D/setA_ui.sh" shot "$S" "$SHOT"
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Share"' && echo "SHARED $(date -u +%T)"
