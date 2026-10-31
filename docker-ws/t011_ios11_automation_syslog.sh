#!/bin/bash
# Read-only: capture ONLY automation-mode related iPhone 11 syslog lines for N seconds (no app content).
#   host-run bash docker-ws/t011_ios11_automation_syslog.sh <out-file-in-repo> <secs>
cd "$(dirname "$0")/.."
O="$1"; N="${2:-150}"; U=00008030-001A6D2801BB802E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(grep --line-buffered -i -E "automationmode|automation mode|evaluatePolicy|LocalAuthentication|testmanagerd.*(automation|auth)|coreauthd.*(passcode|policy)" > "$O") &
P=$!; sleep "$N"; kill "$P" 2>/dev/null; sleep 1
wc -l < "$O"
