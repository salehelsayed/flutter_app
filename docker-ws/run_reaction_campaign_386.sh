#!/bin/bash
# Plan 386 TC-386-11 — device closure for G16 (dead provider grammar) and G20
# (unsound capture substrate).
#
# Runs the reaction catalog campaign end to end on relay v1.8.0. Before this
# plan every fresh capture died on a 2-minute wait for `[PUSH] Notification
# sent to <prefix>`, a line relay `8d86501e4` deleted; provider evidence is now
# an exact `relay_group_reaction_wake_total` delta, and every graded log read
# comes from a live `adb logcat` stream with byte-offset cursors.
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
export FIREBASE_SERVICE_ACCOUNT="$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export MKNOON_257_STAGING_MANIFEST="$REPO/docker-ws/group-reaction-staging-manifest-315.json"
# 21071FDF600CSC = physical Pixel 6 (scenario RECIPIENT); emulator-5554 =
# sdk_gphone16k_arm64 (scenario SENDER).
export SIMS_ANDROID_PHYSICAL_DEVICE_ID='21071FDF600CSC'
export SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554'

[ -f "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$MKNOON_257_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }
[ -f "$MKNOON_257_STAGING_MANIFEST" ] || { echo "FATAL: staging manifest missing"; exit 2; }

# The relay's `/metrics` endpoint is the provider oracle now. If it is not
# readable over the capture's own ssh channel, every counter delta would be
# unattributable and the lane would red for an environment reason.
#
# Keyed on `relay_group_inbox_retrieves_total`, a PLAIN counter that is exported
# from registration onward — never on the graded families. Both of those are
# labelled CounterVecs, and Prometheus exports nothing for a labelled family
# until some label combination has been incremented, so a freshly restarted
# relay serves a healthy 53 KB exposition with zero wake-counter lines.
ssh -o BatchMode=yes -o ConnectTimeout=15 -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" 'curl -sS --max-time 15 http://127.0.0.1:2112/metrics' |
  grep -q relay_group_inbox_retrieves_total || {
    echo "BLOCKED(environment): relay :2112/metrics is not serving a Prometheus exposition"
    exit 2
  }

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

exec bash .claude/skills/sims/scripts/run_with_devices.sh major "$@" --only groups.reaction_notification_campaign
