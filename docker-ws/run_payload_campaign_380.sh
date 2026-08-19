#!/bin/bash
# Plan 380 device closure — notifications.android_payload_campaign.
#
# Nine scenarios in one campaign: A6, B11, B12 warm/cold (now with measured
# audible-channel evidence), B13 dual-path, and the four PRD 13 Android matrix
# legs (permission denied, mid-session token refresh, channel disabled, Doze).
#
# Must run HOST-side: `/claude-host-bin/host-run bash docker-ws/run_payload_campaign_380.sh`.
# The container->Mac tool bridge does not forward environment variables, so
# exporting these in the container leaves the sims planner blocked on
# `environment` / `credentials`. Mirrors run_muted_campaign_383.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# Peer id + listen addresses read live off the relay (v1.8.0, 2026-08-18) and
# identical to the app's built-in constant, network_constants.dart:15.
export MKNOON_RELAY_ADDRESSES='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'

# The campaign resolves the relay through SIMS_NOTIFICATION_* first and falls
# back to MKNOON_*; both are set so the run does not depend on which fallback
# arm is taken (run_notification_tap_device_real.dart:244-253).
export SIMS_NOTIFICATION_RELAY_TARGET='ubuntu@mknoun.xyz'
export MKNOON_RELAY_TARGET='ubuntu@mknoun.xyz'
export SIMS_NOTIFICATION_RELAY_KEY="$REPO/se.pem"
export MKNOON_RELAY_KEY="$REPO/se.pem"

# The campaign only GATES on the service account (_isUsableServiceAccount) —
# the FCM send itself is performed by the relay, which holds its own copy of
# the same mknoon-c6e62 credential.
export SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export FIREBASE_SERVICE_ACCOUNT="$SIMS_PROVIDER_FCM_CREDENTIAL_PATH"

# 21071FDF600CSC = physical Pixel 6, Android 16 / SDK 36 — the SENDER.
# emulator-5554 = sdk_gphone16k_arm64, Android 17 / SDK 37 — the RECEIVER, and
# the only target whose UI the campaign drives (the Pixel sits behind a secure
# keyguard, which is fine because the sender is `am start` + run-as only).
export SIMS_ANDROID_PHYSICAL_DEVICE_ID='21071FDF600CSC'
export SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554'

[ -f "$SIMS_PROVIDER_FCM_CREDENTIAL_PATH" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$SIMS_NOTIFICATION_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }

# SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM is deliberately NOT exported here: the
# executor strips every SIMS_ARTIFACT_* and re-injects it from the prepared
# build, so the stamped APK always matches the working tree. Plan 380 edits
# lib/core/debug/android_notification_payload_e2e{,_protocol}.dart, which sit in
# the cache-key import closure, so expect a full Android rebuild on first run.

exec bash .claude/skills/sims/scripts/run_with_devices.sh major "$@" \
  --only notifications.android_payload_campaign
