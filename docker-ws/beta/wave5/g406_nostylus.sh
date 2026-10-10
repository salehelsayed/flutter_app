#!/bin/bash
# Plan 406: close Gboard's "Try out your stylus" tutorial and turn stylus
# handwriting off on both emulators so it cannot cover the app again.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
ADBB=$ANDROID_HOME/platform-tools/adb
for S in emulator-5554 emulator-5556; do
  $ADBB -s $S shell settings put secure stylus_handwriting_enabled 0
  $ADBB -s $S shell settings put global stylus_handwriting_enabled 0 2>/dev/null
  echo "$S stylus_handwriting_enabled=$($ADBB -s $S shell settings get secure stylus_handwriting_enabled | tr -d '\r')"
done
# Close the tutorial if it is showing on Alice.
maestro --device emulator-5554 test /dev/stdin >/dev/null 2>&1 <<'EOF'
appId: com.google.android.inputmethod.latin
---
- runFlow:
    when:
      visible: Try out your stylus
    commands:
      - tapOn: Cancel
EOF
$ADBB -s emulator-5554 shell dumpsys window | grep -m1 mCurrentFocus
