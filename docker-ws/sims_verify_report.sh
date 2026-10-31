#!/bin/bash
# Re-run the sims report integrity check for one report, with no 120 s cap (the runner's cap expired under high load).
#   host-run bash docker-ws/sims_verify_report.sh <tree under build/> <report-path-relative-to-main-checkout> <out-log-relative>
set -u
M=/Volumes/CrucialX9/flutter_app; cd "$M/build/$1" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/bin:/bin"
start=$(date +%s); dart tool/sims/sims.dart verify-report "$M/$2" > "$M/$3" 2>&1; rc=$?
echo "verify exit=$rc seconds=$(( $(date +%s)-start ))"; tail -5 "$M/$3"; exit $rc
