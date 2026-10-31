#!/bin/bash
# Stream ONE iPhone's syslog to a file in the shared checkout.
#   ./docker-ws/capture_iphone_syslog_any.sh <udid> [out-basename] [process]
#
# Filtered to a single process by default. The unfiltered device firehose is
# ~1 MB/s and repeatedly killed the capture mid-run (2026-08-21); the Runner
# filter keeps every Dart [FLOW] line while cutting volume ~100x.
# Only ONE idevicesyslog may hold the relay per device: strays make a later
# capture connect and then receive nothing. Kill them first.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
UDID="${1:?usage: capture_iphone_syslog_any.sh <udid> [out] [process]}"
OUT="$DIR/${2:-iphone_syslog_${UDID:0:8}.txt}"
PROC="${3:-Runner}"
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
# Stop processes by exact PID only: list via ps, filter on the literal command text, re-check that PID's command line, then kill <pid>. No pattern kills.
stop_matching() {  # $1 = text the command line must contain, $2 = optional second text it must also contain
  local pat="$1" pat2="${2:-}" pids pid n=0 a
  pids=$(ps -axo pid=,args= | awk -v pat="$pat" -v pat2="$pat2" -v me="$$" '$1!=me && $2!~/(^|\/)(awk|ps|grep|pgrep)$/ && index($0,pat) && (pat2=="" || index($0,pat2)) {print $1}')
  for pid in $pids; do
    a=$(ps -o args= -p "$pid" 2>/dev/null)
    case "$a" in *"$pat"*) case "$a" in *"$pat2"*) kill "$pid" 2>/dev/null && { echo "stopped $pid: ${a:0:100}"; n=$((n+1)); };; esac;; esac
  done
  [ "$n" -gt 0 ]
}
stop_matching "idevicesyslog -u $UDID" >/dev/null
sleep 1
exec "$BIN" -u "$UDID" --process "$PROC" > "$OUT" 2>&1
