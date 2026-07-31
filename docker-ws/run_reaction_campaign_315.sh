#!/bin/bash
# Wrapper: export the env the reaction-notification sims lane requires, then run it.
# Values mirror the capture script's own defaults (production relay + repo creds).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export MKNOON_RELAY_ADDRESSES='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
export MKNOON_257_RELAY_TARGET='ubuntu@mknoun.xyz'
export MKNOON_257_RELAY_KEY="$REPO/se.pem"
export FIREBASE_SERVICE_ACCOUNT="$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export MKNOON_257_STAGING_MANIFEST="$REPO/docker-ws/group-reaction-staging-manifest-315.json"
export SIMS_ANDROID_PHYSICAL_DEVICE_ID='21071FDF600CSC'
export SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554'

[ -f "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$MKNOON_257_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }
[ -f "$MKNOON_257_STAGING_MANIFEST" ] || { echo "FATAL: staging manifest missing"; exit 2; }

exec bash .claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign
