#!/bin/bash
# AliceH (E2E build, test relay) adds the iPhone 13 from its decoded QR payload.
ADBB=$HOME/Library/Android/sdk/platform-tools/adb; PKG=com.mknoon.app
CFG=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406/alice_add_iphone.json
$ADBB -s emulator-5554 shell am force-stop $PKG
cat "$CFG" | $ADBB -s emulator-5554 shell "run-as $PKG sh -c 'cat > app_flutter/intro_e2e_config.json'"
$ADBB -s emulator-5554 logcat -c
$ADBB -s emulator-5554 shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 25
echo "ADD_CONTACT_SUCCESS: $($ADBB -s emulator-5554 logcat -d | grep -c ADD_CONTACT_SUCCESS)"
$ADBB -s emulator-5554 logcat -d | grep -oE '"event":"(ADD_CONTACT|CONTACT_REQUEST)[A-Z_]*"' | sort | uniq -c | head -8
