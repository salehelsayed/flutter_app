#!/bin/bash
# Plan 383 (G17) TC-383-10 — device closure for the killed-app typed-event
# fallback lane. Mirrors run_reaction_campaign_315.sh, but selects Plan 379's
# muted-group campaign whose UNMUTED pipeline-health control is this plan's
# gate. Must run HOST-side (`/claude-host-bin/host-run bash docker-ws/...`):
# the container->Mac tool bridge does not forward environment variables, so
# exporting these in the container leaves the sims planner blocked on
# `environment`.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export MKNOON_RELAY_ADDRESSES='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
export MKNOON_257_RELAY_TARGET='ubuntu@mknoun.xyz'
export MKNOON_257_RELAY_KEY="$REPO/se.pem"
export FIREBASE_SERVICE_ACCOUNT="$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export MKNOON_257_STAGING_MANIFEST="$REPO/docker-ws/group-reaction-staging-manifest-315.json"
# 21071FDF600CSC = physical Pixel 6 (scenario RECIPIENT); emulator-5554 =
# sdk_gphone16k_arm64 (scenario SENDER). Both pinned by Plan 379.
export SIMS_ANDROID_PHYSICAL_DEVICE_ID='21071FDF600CSC'
export SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554'

[ -f "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$MKNOON_257_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }
[ -f "$MKNOON_257_STAGING_MANIFEST" ] || { echo "FATAL: staging manifest missing"; exit 2; }

exec bash .claude/skills/sims/scripts/run_with_devices.sh major "$@" --only groups.muted_notification_campaign
