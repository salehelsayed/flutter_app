#!/bin/bash
# Read-only: build / test / install / validation progress for the R2-1 fix check.
. "$(dirname "$0")/beta_env.sh"
echo "now $(date '+%H:%M:%S') load $(sysctl -n vm.loadavg)"
echo "--- build"; cat "$BETA/build/result.txt" 2>/dev/null | tail -8
echo "--- dart tests"; tail -3 /Volumes/CrucialX9/flutter_app/build/r2fix-dart-tests/flutter_test.log 2>/dev/null | cut -c1-200
pgrep -f run_r2fix_dart_tests.sh >/dev/null && echo "(tests running)"
echo "--- install"; tail -6 "$(dirname "$0")/install_r2fix.out" 2>/dev/null
echo "--- validate"; [ -f "$BETA/current_run.txt" ] && tail -12 "$(cat "$BETA/current_run.txt")/timeline.txt" 2>/dev/null
pgrep -f run_r2fix_validate.sh >/dev/null && echo "#VALIDATE_ALIVE" || echo "#VALIDATE_DEAD"
