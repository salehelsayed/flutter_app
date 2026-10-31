#!/bin/bash
# DC-023 recheck: on a fresh Mknoon first-run screen (already launched), onboard, rename and import a QR payload file via Paste QR Data.
#   dc023_onboard.sh <serial> <name> <qr-payload-file>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; N="$2"; QR="$3"; D="$(dirname "$0")"
bash "$D/setA_ui.sh" tap "$S" "I'm new here" || exit 3
for i in $(seq 1 20); do sleep 3; bash "$D/setA_ui.sh" texts "$S" | grep -q "@Username" && break; done
bash "$D/orbit_fill_rename.sh" "$S" "$N"
bash "$D/setA_ui.sh" tap "$S" "Scan a friend" || exit 4; sleep 4
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Paste QR Data"' || exit 4; sleep 3
bash "$D/setA_ui.sh" tap "$S" 'android.widget.EditText'; sleep 1
python3 "$D/setA_type_file.py" "$S" "$QR" | grep MATCH
bash "$D/setA_ui.sh" tap "$S" 'content-desc="Submit"'; sleep 5
bash "$D/setA_ui.sh" texts "$S" | grep -E 'Added|Already|rror|request|Request'
