#!/bin/bash
# On the Mknoon first-run screen of a disposable emulator: tap @Username, replace it with <name>, press Enter.
#   orbit_fill_rename.sh <serial> <name-without-spaces>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="$1"; N="$2"; D="$(dirname "$0")"
bash "$D/setA_ui.sh" texts "$S" | grep -q 'text="Username"' || bash "$D/setA_ui.sh" tap "$S" "@Username"
sleep 2
bash "$D/setA_ui.sh" tap "$S" 'text="Username"'; sleep 1
adb -s "$S" shell input keyevent 123
adb -s "$S" shell input keyevent $(printf '67 %.0s' $(seq 1 12))
adb -s "$S" shell input text "$N"; sleep 1
adb -s "$S" shell input keyevent 66; sleep 2
bash "$D/setA_ui.sh" texts "$S" | grep -E "@|$N" | head -3
