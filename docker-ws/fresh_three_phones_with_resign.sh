#!/bin/bash
# Fresh-identity deploy to iPhone 11 + iPhone 13 + Pixel, with the recurring
# iOS code-seal break repaired automatically.
#
# run_fresh_three_phones.sh uninstalls before installing, so when the
# Flutter.framework seal breaks (ApplicationVerificationFailed 0xe8008001 —
# happens on essentially every iOS build here) it leaves both iPhones with NO
# app. This wrapper runs it, and if it fails, runs resign_and_install_iphones.sh
# to re-sign and install the SAME artifact. Identity is still fresh: the
# uninstall already happened in phase 1.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "########## PHASE 1: fresh build + uninstall + install ##########"
docker-ws/run_fresh_three_phones.sh
PHASE1=$?
echo "########## PHASE 1 exit=$PHASE1 ##########"

if [ "$PHASE1" -eq 0 ]; then
  echo "All three phones OK on the first pass — no re-sign needed."
  exit 0
fi

if ! grep -q 'FAILED(install)' docker-ws/run_fresh_three_phones_result.txt 2>/dev/null; then
  echo "Phase 1 failed for a reason other than an iPhone install — NOT re-signing."
  echo "Look at docker-ws/run_fresh_three_phones_result.txt."
  exit "$PHASE1"
fi

echo "########## PHASE 2: re-sign Flutter.framework + app, reinstall iPhones ##########"
docker-ws/resign_and_install_iphones.sh
PHASE2=$?
echo "########## PHASE 2 exit=$PHASE2 ##########"

echo "########## FINAL ##########"
cat docker-ws/run_fresh_three_phones_result.txt
echo "--- after re-sign ---"
cat docker-ws/resign_and_install_iphones_result.txt 2>/dev/null
exit "$PHASE2"
