#!/bin/bash
# PR 7 simulator check: does tapping a direct-reaction notification open the chat?
# Usage: pr7_sim_test.sh <label>   (label = fix | main; app from pr7_sim_build.sh)
# Sim B (iPhone 16e) only provides a real identity; sim A (iPhone 17) is seeded
# with B as a contact, closed, sent a fake message_reaction push, and the banner
# is tapped with Maestro. Self-detaches; log in pr7_test_<label>.log.
set -u
LABEL=$1
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/pr7_test_$LABEL.log
if [ -z "${PR7_TEST_DETACHED:-}" ]; then
  PR7_TEST_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/.maestro/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
A=8E31AD68-4DBF-4336-AEBF-18148DC9FA07   # iPhone 17, iOS 26.5
B=DBE8C32E-9F19-4593-860A-B41113791D79   # iPhone 16e, iOS 26.5
APP=/Volumes/CrucialX9/flutter_app-pr7-$LABEL/build/ios/iphonesimulator/Runner.app
EV=$W/pr7_evidence_$LABEL; rm -rf "$EV"; mkdir -p "$EV"
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist") || { echo "no app"; exit 1; }
echo "$(date +%T) label=$LABEL bundle=$BID"
wait_file() { for _ in $(seq 1 90); do [ -s "$1" ] && return 0; sleep 2; done; return 1; }

for D in $A $B; do
  xcrun simctl boot $D 2>/dev/null; xcrun simctl bootstatus $D -b >/dev/null
  xcrun simctl uninstall $D "$BID" 2>/dev/null
  xcrun simctl install $D "$APP" || { echo "install failed on $D"; exit 1; }
done
DA=$(xcrun simctl get_app_container $A "$BID" data)/Documents
DB=$(xcrun simctl get_app_container $B "$BID" data)/Documents
mkdir -p "$DA" "$DB"
echo '{"username":"Ios"}' >"$DA/auto_setup.json"
echo '{"username":"Bob"}' >"$DB/auto_setup.json"

echo "$(date +%T) first launch of both (identity)"
xcrun simctl launch $B "$BID" >/dev/null; xcrun simctl launch $A "$BID" >/dev/null
wait_file "$DB/intro_e2e_identity.json" || { echo "B identity missing"; ls "$DB"; exit 1; }
wait_file "$DA/intro_e2e_identity.json" || { echo "A identity missing"; ls "$DA"; exit 1; }
xcrun simctl terminate $B "$BID"; xcrun simctl terminate $A "$BID"

BOB_PEER=$(python3 -c "import json,sys;q=json.loads(json.load(open(sys.argv[1]))['qrPayload']);print(q['ns'])" "$DB/intro_e2e_identity.json")
echo "bob peer=$BOB_PEER"
python3 - "$DB/intro_e2e_identity.json" "$DA/intro_e2e_config.json" <<'EOF'
import json, sys
idn = json.load(open(sys.argv[1]))
json.dump({"stepId": "seed", "add_contacts": [{"qrPayload": idn["qrPayload"], "mlKemPublicKey": idn["mlKemPublicKey"]}]}, open(sys.argv[2], "w"))
EOF

echo "$(date +%T) relaunch A with Bob seeded"
xcrun simctl spawn $A log stream --style compact --level debug --predicate 'process == "Runner"' >"$EV/runner.log" 2>&1 &
LOGPID=$!; sleep 3
xcrun simctl launch $A "$BID" >/dev/null
maestro --device $A test --test-output-dir "$EV/allow_out" -e APP_ID="$BID" $W/pr7_allow.yaml >"$EV/allow.log" 2>&1
echo "allow flow exit=$? ($(grep -c 'Allow' "$EV/allow.log") Allow lines; $(grep -cE 'Tap on .\^Allow' "$EV/allow.log") taps)"
grep -E 'permission|PUSH_REGISTER' "$EV/runner.log" | cut -c1-200 | tail -4
xcrun simctl terminate $A "$BID"; sleep 3
cat >"$EV/push.json" <<EOF
{"aps":{"alert":{"title":"Bob","body":"Reacted 👍 to your message"},"sound":"default"},
 "type":"message_reaction","sender_id":"$BOB_PEER","event_id":"pr7-sim-event-1",
 "target_message_id":"pr7-sim-target-1","action":"add","capability_version":"1"}
EOF
echo "$(date +%T) push while app is closed"
xcrun simctl push $A "$BID" "$EV/push.json"; sleep 3
maestro --device $A test --test-output-dir "$EV/tap_out" -e APP_ID="$BID" -e MESSAGE_PATTERN=".*Reacted.*" \
  $W/pr7_tap.yaml >"$EV/tap.log" 2>&1
echo "tap flow exit=$? (0 = chat composer visible)"
sleep 5
kill $LOGPID 2>/dev/null
echo "=== key log lines ==="
grep -E 'ios_notification_open|IOS_APNS_NOTIFICATION_OPENED|NOTIFICATION_TAP_TO_MESSAGE_TIMING|ROUTE_ERROR|ROUTE_ATTEMPT_ERROR|ROUTE_ALREADY_ACTIVE' "$EV/runner.log" | cut -c1-260 | head -20
echo "=== tap flow tail ==="; tail -12 "$EV/tap.log"
echo "$(date +%T) done"
