#!/bin/bash
# Voice-playback repro: fresh install on two emulators, auto identities, make them friends.
# Alice = emulator-5554 (Pixel_7), Bob = emulator-5556 (Pixel_8).
set -u
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
PKG=com.mknoon.app
APK=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/voice/app.apk
declare_name() { [ "$1" = emulator-5554 ] && echo Alice || echo Bob; }
wr() { $ADBB -s "$1" shell "run-as $PKG sh -c 'mkdir -p app_flutter && cat > app_flutter/$2'"; }
rd() { $ADBB -s "$1" shell "run-as $PKG cat app_flutter/$2" 2>/dev/null; }
for S in emulator-5554 emulator-5556; do
  $ADBB -s $S shell svc power stayon true
  $ADBB -s $S shell settings put system screen_off_timeout 1800000
  $ADBB -s $S shell am force-stop $PKG; $ADBB -s $S uninstall $PKG >/dev/null 2>&1
  $ADBB -s $S install -r -g "$APK" | tail -1
  echo "{\"username\":\"$(declare_name $S)\"}" | wr $S auto_setup.json
  $ADBB -s $S shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
done
A=""; B=""
for i in $(seq 1 90); do
  [ -z "$A" ] && A=$(rd emulator-5554 intro_e2e_identity.json)
  [ -z "$B" ] && B=$(rd emulator-5556 intro_e2e_identity.json)
  [ -n "$A" ] && [ -n "$B" ] && break; sleep 2
done
[ -z "$A" ] || [ -z "$B" ] && { echo "FAILED identity export A=${#A} B=${#B}"; exit 1; }
card() { python3 -c "import json,sys;d=json.loads(sys.argv[1]);print(json.dumps({'stepId':'seed','add_contacts':[{'qrPayload':d['qrPayload'],'mlKemPublicKey':d['mlKemPublicKey']}]}))" "$1"; }
for S in emulator-5554 emulator-5556; do $ADBB -s $S shell am force-stop $PKG; done
card "$B" | wr emulator-5554 intro_e2e_config.json
card "$A" | wr emulator-5556 intro_e2e_config.json
for S in emulator-5554 emulator-5556; do
  $ADBB -s $S logcat -c
  $ADBB -s $S shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
done
sleep 20
for S in emulator-5554 emulator-5556; do
  echo "$S $(declare_name $S): $($ADBB -s $S logcat -d | grep -c ADD_CONTACT_SUCCESS) ADD_CONTACT_SUCCESS; config left: $(rd $S intro_e2e_config.json | wc -c | tr -d ' ') bytes"
done
