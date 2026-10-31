#!/bin/bash
# Owner 2026-10-26: "the tests should run on aws not hetzner": run ONLY device-group-mute /
# device-notifications-android against the AWS relay (read-only systemctl/journalctl over SSH). Keys are passed BY PATH and never opened or printed.
#   host-run bash docker-ws/hetzner_campaigns.sh <check-id> <evidence-dir-relative> [tree]
set -uo pipefail
case "$1" in device-group-mute|device-notifications-android) ;; *) echo "refused: check not approved"; exit 2;; esac
M=/Volumes/CrucialX9/flutter_app; EV="$M/$2"
export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
SK="$M/se.pem"; [ -f "$SK" ] || { echo "relay SSH key missing"; exit 3; }
MF="$EV/aws-relay-manifest.json"; [ -f "$MF" ] || { echo "manifest missing"; exit 3; }
K=$(find "$M" -maxdepth 1 -type f -iname '*firebase-adminsdk*.json' | head -1); [ -n "$K" ] || { echo "FCM key not found by name"; exit 3; }
PID=12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
export MKNOON_RELAY_ADDRESSES="/dns4/mknoun.xyz/tcp/4001/wss/p2p/$PID,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/$PID"
export SIMS_NOTIFICATION_RELAY_TARGET=ubuntu@51.21.194.144 MKNOON_RELAY_TARGET=ubuntu@51.21.194.144 MKNOON_257_RELAY_TARGET=ubuntu@51.21.194.144
export SIMS_NOTIFICATION_RELAY_KEY="$SK" MKNOON_RELAY_KEY="$SK" MKNOON_257_RELAY_KEY="$SK"
export MKNOON_257_STAGING_MANIFEST="$MF"
export FIREBASE_SERVICE_ACCOUNT="$K" SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$K"
echo "key paths set, relay target = AWS relay"
# The Pixel lay sideways with auto-rotate on, so Group Info rendered landscape and the campaign's portrait swipe
# never reached the mute row. Lock portrait for the run, then restore the owner's rotation settings.
P=21071FDF600CSC; AR=$(adb -s $P shell settings get system accelerometer_rotation | tr -d '\r'); UR=$(adb -s $P shell settings get system user_rotation | tr -d '\r')
adb -s $P shell settings put system accelerometer_rotation 0; adb -s $P shell settings put system user_rotation 0
echo "pixel rotation locked to portrait (was accelerometer_rotation=$AR user_rotation=$UR)"
bash "$(dirname "$0")/step4_main_campaigns.sh" run "$1" "$2" "${3:-wt-fb}"; rc=$?
adb -s $P shell settings put system accelerometer_rotation "$AR"; adb -s $P shell settings put system user_rotation "$UR"
echo "pixel rotation restored"; exit $rc
