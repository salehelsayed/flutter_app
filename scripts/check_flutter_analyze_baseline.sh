#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 2

baseline_file="${ANALYZER_BASELINE_FILE:-tool/analyzer_baseline/flutter_analyze_baseline.tsv}"
log_file="${ANALYZER_BASELINE_LOG_PATH:-}"
cleanup_log=0

if [[ -z "$log_file" ]]; then
  log_file="$(mktemp "${TMPDIR:-/tmp}/flutter_analyze_baseline.XXXXXX.log")"
  cleanup_log=1
fi

echo "Running flutter analyze baseline gate"
echo "Baseline: $baseline_file"
echo "Analyzer log: $log_file"

flutter analyze --no-fatal-infos --no-fatal-warnings >"$log_file" 2>&1
analyze_status=$?

dart run tool/analyzer_baseline/analyzer_baseline.dart compare \
  --input "$log_file" \
  --baseline "$baseline_file"
compare_status=$?

if [[ "$compare_status" -ne 0 || "$analyze_status" -ne 0 ]]; then
  echo "Analyzer log retained: $log_file" >&2
  cleanup_log=0
fi

if [[ "$cleanup_log" -eq 1 && "${ANALYZER_BASELINE_KEEP_LOG:-0}" != "1" ]]; then
  rm -f "$log_file"
fi

if [[ "$compare_status" -ne 0 ]]; then
  exit "$compare_status"
fi

if [[ "$analyze_status" -ne 0 ]]; then
  echo "flutter analyze exited $analyze_status even though baseline comparison passed." >&2
  exit "$analyze_status"
fi

exit 0
