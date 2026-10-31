#!/bin/bash
# Owner-approved 2026-10-25: run ONLY device-group-mute / device-notifications-android with the production FCM
# service-account key passed BY PATH. The key is located by file name and never opened, printed or copied.
#   host-run bash docker-ws/fcm_campaigns.sh <check-id> <evidence-dir-relative> [tree]
set -uo pipefail
case "$1" in device-group-mute|device-notifications-android) ;; *) echo "refused: check not approved for the FCM key"; exit 2;; esac
K=$(find /Volumes/CrucialX9/flutter_app -maxdepth 1 -type f -iname '*firebase-adminsdk*.json' | head -1)
[ -n "$K" ] || { echo "key file not found by name"; exit 3; }
export FIREBASE_SERVICE_ACCOUNT="$K" SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$K"
echo "key path set"
exec bash "$(dirname "$0")/step4_main_campaigns.sh" run "$1" "$2" "${3:-wt-fb}"
