#!/bin/bash
# Plan 386 TC-386-10 — device closure for the G18 self-reaction leg.
#
# Selects Plan 379's muted-group campaign, whose backgrounded reaction scenario
# now carries one extra graded step: the SENDER reacts to its own warm-up
# message in the control group, and the relay's counters must show exactly one
# empty wake nomination and zero wake attempts.
#
# Must run HOST-side (`/claude-host-bin/host-run bash docker-ws/...`): the
# container->Mac tool bridge does not forward environment variables, so
# exporting these in the container leaves the sims planner blocked on
# `environment`. `host-run bash -c` is refused, which is why this is a
# repo-resident script rather than an inline command.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

export MKNOON_RELAY_ADDRESSES='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
export MKNOON_257_RELAY_TARGET='ubuntu@mknoun.xyz'
export MKNOON_257_RELAY_KEY="$REPO/se.pem"
export FIREBASE_SERVICE_ACCOUNT="$REPO/mknoun-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export MKNOON_257_STAGING_MANIFEST="$REPO/docker-ws/group-reaction-staging-manifest-315.json"
# 21071FDF600CSC = physical Pixel 6 (scenario RECIPIENT); emulator-5554 =
# sdk_gphone16k_arm64 (scenario SENDER). Both pinned by Plan 379.
export SIMS_ANDROID_PHYSICAL_DEVICE_ID='21071FDF600CSC'
export SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554'

[ -f "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$MKNOON_257_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }
[ -f "$MKNOON_257_STAGING_MANIFEST" ] || { echo "FATAL: staging manifest missing"; exit 2; }

# The physical device drives real UI. A secure keyguard silently swallows every
# tap, which reads downstream as a product failure rather than an environment
# blocker, so stop here with a named reason instead.
# `mIsShowing` under KeyguardStateMonitor is the signal this device actually
# prints; `isStatusBarKeyguard` does not appear in its dumpsys at all, so a
# check keyed on that would pass while the device sat locked.
if adb -s "$SIMS_ANDROID_PHYSICAL_DEVICE_ID" shell dumpsys window policy 2>/dev/null |
     grep -qE 'mIsShowing=true'; then
  echo "BLOCKED(environment): $SIMS_ANDROID_PHYSICAL_DEVICE_ID is on the keyguard; unlock it before this lane drives its UI"
  exit 2
fi

exec bash .claude/skills/sims/scripts/run_with_devices.sh major "$@" --only groups.muted_notification_campaign
