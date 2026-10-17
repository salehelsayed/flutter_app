#!/bin/bash
# SE-55 check: build the current tree (flow log, voice calls) and install it on the iPhone 11 ONLY,
# keeping app data. The iPhone 13 must stay on build 125.
cd /Volumes/CrucialX9/flutter_app || exit 1
. docker-ws/local_devices.env || exit 2
EV="${1:?evidence dir}"; mkdir -p "$EV"; OUT="$EV/iphone11_deploy.txt"
{
  echo "=== start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD)"
  bash docker-ws/build_ios_flowlog.sh || { echo "SE55 BUILD FAILED"; exit 1; }
  IPHONE_UDIDS="${IPHONE11_UDID:?}" bash docker-ws/install_iphones_keep_identity.sh
  echo "SE55 DEPLOY EXIT $?"
} > "$OUT" 2>&1
rc=$?; tail -6 "$OUT"; exit $rc
