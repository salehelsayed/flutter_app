#!/bin/bash
# O10 (2026-10-04): build the current tree for iOS with FDC_FLOW_LOG and install it on the iPhone 13 only,
# keeping app data (replaces the UI-Update prototype build there, by user decision).
cd /Volumes/CrucialX9/flutter_app || exit 1
OUT=docker-ws/beta/r48_o10_ios_deploy.out
{
  echo "=== start $(date -u +%FT%TZ)"
  bash docker-ws/build_ios_flowlog.sh || { echo "R48 BUILD FAILED"; exit 1; }
  IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
  echo "R48 EXIT $?"
} > "$OUT" 2>&1
tail -6 "$OUT"
