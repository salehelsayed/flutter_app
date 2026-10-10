#!/bin/bash
# Plan 406: press Back on an emulator (closes the Gboard stylus tutorial), then
# save a screenshot to wave5/g406/<serial>.png.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
ADBB=$ANDROID_HOME/platform-tools/adb
S=${1:-emulator-5554}
[ "${2:-back}" = back ] && $ADBB -s $S shell input keyevent 4
sleep 2
$ADBB -s $S exec-out screencap -p > /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406/$S.png
echo "saved $S.png"
