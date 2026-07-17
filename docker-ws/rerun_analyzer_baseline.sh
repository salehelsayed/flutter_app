#!/bin/bash
# Rerun ONLY the analyzer baseline gate, persisting the log + comparison
# output into docker-ws so Claude can read them from the sandbox.
# Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/rerun_analyzer_baseline.sh
cd "$(dirname "$0")/.." || exit 2
export ANALYZER_BASELINE_LOG_PATH=docker-ws/flutter_analyze_log.txt
OUT=docker-ws/analyzer_baseline_result.txt
rm -f "$OUT"
TMP=$(mktemp)
./scripts/check_flutter_analyze_baseline.sh >"$TMP" 2>&1
echo "exit=$?" >> "$TMP"
mv "$TMP" "$OUT"
tail -20 "$OUT"
