#!/bin/bash
# Read-only: R2-3 build / test / install / validation progress.
. "$(dirname "$0")/beta_env.sh"
echo "now $(date '+%H:%M:%S') load $(sysctl -n vm.loadavg)"
echo "--- build"; tail -6 "$BETA/build-r2-3/result.txt" 2>/dev/null
pgrep -f build_r23.sh >/dev/null && echo "(build running)"
echo "--- dart tests"; cat /Volumes/CrucialX9/flutter_app/build/r23-dart-tests/status.txt 2>/dev/null
pgrep -f run_r23_dart_tests.sh >/dev/null && echo "(tests running)"
echo "--- install"; tail -6 "$(dirname "$0")/install_r23.out" 2>/dev/null
echo "--- validate"; tail -14 "$(cat "$BETA/current_run.txt")/timeline.txt" 2>/dev/null | cut -c1-400
pgrep -f run_r23_validate.sh >/dev/null && echo "#VALIDATE_ALIVE" || echo "#VALIDATE_DEAD"
