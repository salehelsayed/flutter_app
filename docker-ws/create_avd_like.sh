#!/bin/bash
# Create a disposable AVD <new> with the same system image and device profile as <source>. Refuses if <new> exists.
#   host-run bash docker-ws/create_avd_like.sh <source> <new>
set -uo pipefail
SRC="${1:?source}"; NEW="${2:?new}"
[[ "$NEW" =~ ^[A-Za-z0-9_]+$ ]] || { echo "bad name"; exit 2; }
SDK="$HOME/Library/Android/sdk"; AVDHOME="$HOME/.android/avd"
CFG="$AVDHOME/$SRC.avd/config.ini"; [ -f "$CFG" ] || CFG="$(sed -n 's/^path=//p' "$AVDHOME/$SRC.ini")/config.ini"
[ -f "$CFG" ] || { echo "no config for $SRC"; exit 2; }
"$SDK/emulator/emulator" -list-avds | grep -qx "$NEW" && { echo "exists: $NEW"; exit 2; }
SYS=$(sed -n 's/^image.sysdir.1=//p' "$CFG" | sed 's#/$##; s#/#;#g'); DEV=$(sed -n 's/^hw.device.name=//p' "$CFG")
echo "image=$SYS device=$DEV"
AVDM=$(ls "$SDK"/cmdline-tools/*/bin/avdmanager 2>/dev/null | head -1)
[ -x "$AVDM" ] || { echo "avdmanager not found"; exit 2; }
echo no | "$AVDM" create avd -n "$NEW" -k "$SYS" -d "$DEV" > /tmp/create_avd_$NEW.log 2>&1; rc=$?
echo "create exit=$rc"; tail -n 3 /tmp/create_avd_$NEW.log; exit $rc
