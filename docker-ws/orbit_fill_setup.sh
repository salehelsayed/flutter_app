#!/bin/bash
# Fresh Mknoon friend on a disposable emulator: reinstall the APK, onboard, rename, import a QR payload file (Paste QR Data),
# push the generated images and media-scan them.
#   orbit_fill_setup.sh <serial> <apk> <name> <qr-payload-file> <image-dir>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; APK="$2"; N="$3"; QR="$4"; IMG="$5"; D="$(dirname "$0")"
adb -s "$S" uninstall com.mknoon.app >/dev/null 2>&1
adb -s "$S" install -r -g "$APK" | tail -1
adb -s "$S" shell mkdir -p /sdcard/Pictures
for f in "$IMG"/*.jpg; do adb -s "$S" push "$f" /sdcard/Pictures/ >/dev/null 2>&1
  adb -s "$S" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Pictures/$(basename "$f")" >/dev/null; done
adb -s "$S" shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in $(seq 1 20); do sleep 3; bash "$D/setA_ui.sh" texts "$S" | grep -q "I'm new here" && break; done
bash "$D/setA_ui.sh" tap "$S" "I'm new here" || exit 3
for i in $(seq 1 20); do sleep 3; bash "$D/setA_ui.sh" texts "$S" | grep -q "@Username" && break; done
bash "$D/orbit_fill_rename.sh" "$S" "$N"
bash "$D/setA_ui.sh" tap "$S" "Scan a friend" || exit 4; sleep 4
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Paste QR Data"' || exit 4; sleep 3
bash "$D/setA_ui.sh" tap "$S" 'android.widget.EditText'; sleep 1
python3 "$D/setA_type_file.py" "$S" "$QR" | grep MATCH
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Submit"'; sleep 5
bash "$D/setA_ui.sh" texts "$S" | grep -E 'Added|Already|rror' 
bash "$D/setA_ui.sh" tap "$S" 'content-desc="OK"'
