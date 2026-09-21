#!/bin/bash
# Full `sims major` run with the campaign environment exported host-side.
#
# Must run HOST-side:
#   /claude-host-bin/host-run bash docker-ws/run_sims_major.sh
#   /claude-host-bin/host-run bash docker-ws/run_sims_major.sh --list
#   /claude-host-bin/host-run bash docker-ws/run_sims_major.sh --simultaneous
#
# The container->Mac tool bridge does not forward environment variables, so
# exporting these in the container leaves the sims planner BLOCKED on
# `environment` / `credentials` for 17 of the 43 major rows. Same shape as
# run_payload_campaign_380.sh, but for the whole gate instead of one campaign.
#
# Every value below is overridable from the caller's environment, so a
# one-off run can retarget a device without editing this file.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# --- Relay -----------------------------------------------------------------
# Peer id + listen addresses of the production relay (mknoun.xyz). There is no
# separate staging box; `relay.staging` in the manifest means "a real relay",
# and these are the same addresses the app compiles in
# (network_constants.dart:15).
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"

# SSH custody of the relay box. Notification campaigns read the inbox and seed
# fixtures over this channel; both spellings are set so a run does not depend
# on which fallback arm a runner takes.
export SIMS_NOTIFICATION_RELAY_TARGET="${SIMS_NOTIFICATION_RELAY_TARGET:-ubuntu@mknoun.xyz}"
export MKNOON_RELAY_TARGET="${MKNOON_RELAY_TARGET:-$SIMS_NOTIFICATION_RELAY_TARGET}"
export SIMS_NOTIFICATION_RELAY_KEY="${SIMS_NOTIFICATION_RELAY_KEY:-$REPO/se.pem}"
export MKNOON_RELAY_KEY="${MKNOON_RELAY_KEY:-$SIMS_NOTIFICATION_RELAY_KEY}"

# Plan 257 spelling, read by the seven reaction/projection/muted/strict/
# recovery notification runners.
export MKNOON_257_RELAY_TARGET="${MKNOON_257_RELAY_TARGET:-$SIMS_NOTIFICATION_RELAY_TARGET}"
export MKNOON_257_RELAY_KEY="${MKNOON_257_RELAY_KEY:-$SIMS_NOTIFICATION_RELAY_KEY}"
export MKNOON_257_STAGING_MANIFEST="${MKNOON_257_STAGING_MANIFEST:-$REPO/docker-ws/group-reaction-staging-manifest-315.json}"

# --- Push provider ---------------------------------------------------------
# The runners only GATE on the service account being readable and carrying a
# project_id; the FCM send itself is performed by the relay, which holds its
# own copy of the same mknoon-c6e62 credential.
export SIMS_PROVIDER_FCM_CREDENTIAL_PATH="${SIMS_PROVIDER_FCM_CREDENTIAL_PATH:-$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json}"
export FIREBASE_SERVICE_ACCOUNT="${FIREBASE_SERVICE_ACCOUNT:-$SIMS_PROVIDER_FCM_CREDENTIAL_PATH}"

# --- Android targets -------------------------------------------------------
# 21071FDF600CSC = physical Pixel 6, Android 16 / SDK 36.
# emulator-5554  = sdk_gphone16k_arm64, Android 17 / SDK 37.
# emulator-5556  = sdk_gphone64_arm64, second emulator; only
#                  intro.accept_notification_campaign needs it.
export SIMS_ANDROID_PHYSICAL_DEVICE_ID="${SIMS_ANDROID_PHYSICAL_DEVICE_ID:-21071FDF600CSC}"
export SIMS_ANDROID_EMULATOR_DEVICE_ID="${SIMS_ANDROID_EMULATOR_DEVICE_ID:-emulator-5554}"
export SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID="${SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID:-emulator-5556}"

# --- iOS simulator for the native Runner tests -----------------------------
# native.ios.runner_tests interpolates this straight into the xcodebuild
# -destination. Any available simulator works; it is not mutated.
export SIMS_IOS_SIMULATOR_ID="${SIMS_IOS_SIMULATOR_ID:-674DFFF6-5F38-4235-93F6-AF7FBF86AE65}"

# --- Four disposable simulators for group multi-party ----------------------
# groups.multi_party_release uninstalls Runner and mutates app data on these,
# so the planner demands four distinct UUIDs as explicit authorization.
# Authorized 2026-09-20: the four iPhone simulators on this Mac, all booted.
#   674DFFF6… iPhone 17 Pro   6597ECAD… iPhone Air
#   8E31AD68… iPhone 17       DBE8C32E… iPhone 16e
# Anything installed on these four is expendable.
export SIMS_IOS_DISPOSABLE_SIMULATOR_IDS="${SIMS_IOS_DISPOSABLE_SIMULATOR_IDS:-674DFFF6-5F38-4235-93F6-AF7FBF86AE65,6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76,8E31AD68-4DBF-4336-AEBF-18148DC9FA07,DBE8C32E-9F19-4593-860A-B41113791D79}"

# --- Physical iOS notification boundary ------------------------------------
# Receiver chosen 2026-09-20: the iPhone 11. It is the only device that is both
# paired and listed in the development profile's ProvisionedDevices
# (scripts/test/ios_profile_devices_321.sh). Each run uninstalls com.mknoon.app
# from it, so that phone's app chats and identity are expendable. Nothing else
# on the phone is touched.
export SIMS_IOS_PHYSICAL_DEVICE_ID="${SIMS_IOS_PHYSICAL_DEVICE_ID:-00008030-001A6D2801BB802E}"

# Inputs the pre-build probe needs to MINT the staging attestation
# (integration_test/scripts/ios_notification_provider_adapter.py --action probe).
# The probe hashes the signing leaf itself; signingIdentitySha256 is never
# typed by hand.
export SIMS_IOS_APNS_AUTH_KEY_PATH="${SIMS_IOS_APNS_AUTH_KEY_PATH:-$REPO/APPLE/AuthKey_M7T46H43B2.p8}"
export SIMS_IOS_APNS_KEY_ID="${SIMS_IOS_APNS_KEY_ID:-M7T46H43B2}"
export SIMS_IOS_APNS_TEAM_ID="${SIMS_IOS_APNS_TEAM_ID:-397R9Q4WMX}"
export SIMS_IOS_PROVISIONING_PROFILE_PATH="${SIMS_IOS_PROVISIONING_PROFILE_PATH:-$REPO/build/ios/iphoneos/Runner.app/embedded.mobileprovision}"
export SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER="${SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER:-$REPO/integration_test/scripts/ios_notification_relay_fixture_driver.py}"

# The real driver is the in-repo adapter (probe|setup|retry|cleanup|rollback),
# not the July scaffold under docker-ws/sims-ios-notification/ — that one still
# has unwired TODO seams and is obsolete.
export SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER="${SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER:-$REPO/integration_test/scripts/ios_notification_provider_adapter.py}"

# Minted 2026-09-20 by docker-ws/bootstrap_ios_receiver.sh +
# docker-ws/mint_ios_staging_manifest.sh. Exported only when they really exist,
# so a missing mint stays an honest BLOCKED row instead of a confusing error.
_sims_ios_out="${SIMS_IOS_BOOTSTRAP_OUT_DIR:-$HOME/.mknoon-sims}"
if [ -f "$_sims_ios_out/ios-staging-manifest.json" ] && [ -f "$_sims_ios_out/provider-request.json" ] && [ -x "$_sims_ios_out/iospayloadproducer" ]; then
  export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="${SIMS_IOS_NOTIFICATION_STAGING_MANIFEST:-$_sims_ios_out/ios-staging-manifest.json}"
  export SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST="${SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST:-$_sims_ios_out/provider-request.json}"
  export SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER="${SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER:-$_sims_ios_out/iospayloadproducer}"
fi
# The handoff is deliberately NOT exported: the campaign captures its own with
# its own nonce (ios_notification_payload_xcui_driver.dart:1508-1529). The
# bootstrap capture exists only to mint the attestation.
_sims_manifest_is_real() {
  test -f "$1" && ! grep -q 'FILL_ME' "$1"
}
_ios_staging_default="$REPO/docker-ws/sims-ios-notification/staging-manifest.json"
_ios_request_default="$REPO/docker-ws/sims-ios-notification/provider-request.json"
_ios_driver_default="$REPO/docker-ws/sims-ios-notification/provider_driver.py"
if [ -n "${SIMS_IOS_NOTIFICATION_STAGING_MANIFEST:-}" ]; then
  : # caller supplied its own attestation; trust it and let preflight judge.
elif _sims_manifest_is_real "$_ios_staging_default" && _sims_manifest_is_real "$_ios_request_default"; then
  export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST="$_ios_staging_default"
  export SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST="$_ios_request_default"
  export SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER="${SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER:-$_ios_driver_default}"
fi

# --- Preconditions ---------------------------------------------------------
# --check-env runs the preconditions and the report, then exits without
# touching the gate. Everything else is passed through to the sims CLI.
_list_only=0
_check_env_only=0
_gate_args=()
for _arg in "$@"; do
  if [ "$_arg" = "--list" ] || [ "$_arg" = "--dry-run" ]; then
    _list_only=1
  fi
  if [ "$_arg" = "--check-env" ]; then
    _check_env_only=1
  else
    _gate_args[${#_gate_args[@]}]="$_arg"
  fi
done

[ -f "$SIMS_PROVIDER_FCM_CREDENTIAL_PATH" ] || { echo "FATAL: service account json missing: $SIMS_PROVIDER_FCM_CREDENTIAL_PATH"; exit 2; }
[ -f "$SIMS_NOTIFICATION_RELAY_KEY" ] || { echo "FATAL: relay key missing: $SIMS_NOTIFICATION_RELAY_KEY"; exit 2; }
[ -f "$MKNOON_257_STAGING_MANIFEST" ] || { echo "FATAL: plan-257 staging manifest missing: $MKNOON_257_STAGING_MANIFEST"; exit 2; }

if [ "$_list_only" -eq 0 ]; then
  for _tool in flutter dart go adb xcrun xcodebuild; do
    command -v "$_tool" >/dev/null 2>&1 || { echo "FATAL: $_tool is not on PATH for the host run"; exit 2; }
  done
  _attached="$(adb devices | tail -n +2 | awk '$2 == "device" { print $1 }')"
  for _device in "$SIMS_ANDROID_PHYSICAL_DEVICE_ID" "$SIMS_ANDROID_EMULATOR_DEVICE_ID" "$SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID"; do
    echo "$_attached" | grep -qx "$_device" || { echo "FATAL: android target not attached: $_device"; exit 2; }
  done
fi

# --- Report ----------------------------------------------------------------
echo "sims major environment"
echo "  relay addresses      : ${MKNOON_RELAY_ADDRESSES%%,*} (+1 more)"
echo "  relay ssh target     : $SIMS_NOTIFICATION_RELAY_TARGET"
echo "  fcm credential       : $SIMS_PROVIDER_FCM_CREDENTIAL_PATH"
echo "  android physical     : $SIMS_ANDROID_PHYSICAL_DEVICE_ID"
echo "  android emulator     : $SIMS_ANDROID_EMULATOR_DEVICE_ID"
echo "  android emulator 2   : $SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID"
echo "  ios simulator        : $SIMS_IOS_SIMULATOR_ID"
echo "  disposable ios sims  : $SIMS_IOS_DISPOSABLE_SIMULATOR_IDS"
echo "  ios receiver phone   : $SIMS_IOS_PHYSICAL_DEVICE_ID (iPhone 11)"
echo "  ios staging manifest : ${SIMS_IOS_NOTIFICATION_STAGING_MANIFEST:-<unminted: needs the receiver peer id + provider_driver.py seams; iOS notification rows stay BLOCKED>}"
echo

if [ "$_check_env_only" -eq 1 ]; then
  echo "Environment check only. The gate was not started."
  exit 0
fi

# SIMS_ARTIFACT_* is deliberately NOT exported: the executor strips every
# SIMS_ARTIFACT_* and re-injects it from the prepared build, so the stamped
# app always matches the working tree.
exec bash .claude/skills/sims/scripts/run_with_devices.sh major ${_gate_args[@]+"${_gate_args[@]}"}
