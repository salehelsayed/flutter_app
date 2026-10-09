#!/bin/bash
# Round-3 Android validation (2026-10-08): build the current tree for iOS with FDC_FLOW_LOG and voice calls, and
# install it on the iPhone 13 only, keeping app data (replaces the UI-Update build there, by user decision 2026-10-08).
cd /Volumes/CrucialX9/flutter_app || exit 1
OUT=docker-ws/beta/v3/ios13_deploy.out
{
  echo "=== start $(date -u +%FT%TZ)"
  bash docker-ws/build_ios_flowlog.sh || { echo "V3 BUILD FAILED"; exit 1; }
  IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
  echo "V3 EXIT $?"
} > "$OUT" 2>&1
tail -6 "$OUT"
