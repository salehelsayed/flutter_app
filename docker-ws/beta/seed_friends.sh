#!/bin/bash
# Fresh install on both devices, auto-create identities, then make them friends
# by writing each device's exported contact card into the other's
# intro_e2e_config.json (debug + E2E_TEST_MODE build reads it before runApp).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
LOG="$RUN/seed.log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "[$(date +%H:%M:%S)] $*"; }

say "bundle=$BUNDLE pkg=$PKG build=$(cat "$BETA/build/build_name.txt")"
# --- Android fresh install (-g grants mic/notification/etc.)
$ADB shell am force-stop $PKG
$ADB uninstall $PKG >/dev/null 2>&1
$ADB install -r -g "$BETA/build/beta-android.apk" || { say "FAILED android install"; exit 1; }
say "android versionName: $($ADB shell dumpsys package $PKG | grep -m1 versionName)"
echo "{\"username\":\"$AND_NAME\"}" | and_write auto_setup.json

# --- iOS fresh install
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$BETA/build/Runner.app" || { say "FAILED ios install"; exit 1; }
for s in microphone photos camera; do xcrun simctl privacy "$UDID" grant $s "$BUNDLE"; done
DOCS=$(ios_docs); mkdir -p "$DOCS"
echo "{\"username\":\"$IOS_NAME\"}" > "$DOCS/auto_setup.json"
say "ios docs=$DOCS"

# --- first launch: identity creation + export
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
xcrun simctl launch "$UDID" "$BUNDLE"
AID=""; IID=""
for i in $(seq 1 90); do
  [ -z "$AID" ] && AID=$(and_read intro_e2e_identity.json)
  [ -z "$IID" ] && [ -f "$DOCS/intro_e2e_identity.json" ] && IID=$(cat "$DOCS/intro_e2e_identity.json")
  [ -n "$AID" ] && [ -n "$IID" ] && break
  sleep 2
done
[ -z "$AID" ] && { say "FAILED android identity export (180s)"; exit 1; }
[ -z "$IID" ] && { say "FAILED ios identity export (180s)"; exit 1; }
echo "$AID" > "$RUN/android_identity_export.json"
echo "$IID" > "$RUN/ios_identity_export.json"
say "identities exported"

# --- cross-write friend configs, relaunch
$ADB shell am force-stop $PKG
xcrun simctl terminate "$UDID" "$BUNDLE"
mkcfg() { /usr/bin/python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); print(json.dumps({"stepId":"beta-seed","add_contacts":[{"qrPayload":e["qrPayload"],"mlKemPublicKey":e.get("mlKemPublicKey")}]}))' "$1"; }
mkcfg "$RUN/ios_identity_export.json" | and_write intro_e2e_config.json
mkcfg "$RUN/android_identity_export.json" > "$DOCS/intro_e2e_config.json"
/usr/bin/python3 - "$RUN" <<'PY'
import json,sys
run=sys.argv[1]
for side in ("ios","android"):
    q=json.loads(json.load(open(f"{run}/{side}_identity_export.json"))["qrPayload"])
    print(f"{side} peer: {q.get('pk','')[:0]}{ {k:(str(v)[:24]) for k,v in q.items() if k in ('un','ns','rv')} }")
PY
sleep 2
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
xcrun simctl launch "$UDID" "$BUNDLE"
# The E2E poller deletes the config once consumed.
for i in $(seq 1 60); do
  a=$(and_read intro_e2e_config.json); [ -f "$DOCS/intro_e2e_config.json" ] && b=1 || b=""
  [ -z "$a" ] && [ -z "$b" ] && break
  sleep 2
done
say "config consumed: android=$([ -z "$a" ] && echo yes || echo no) ios=$([ -z "$b" ] && echo yes || echo no)"
$ADB exec-out screencap -p > "$RUN/screens/seed_android.png"
xcrun simctl io "$UDID" screenshot "$RUN/screens/seed_ios.png" >/dev/null 2>&1
say "SEED DONE"
