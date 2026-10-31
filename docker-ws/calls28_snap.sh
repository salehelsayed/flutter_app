#!/bin/bash
# Snapshot both phones after a call step: Pixel native state + last history row, iPhone call labels + last row, and both sides' recent call transitions.
#   calls28_snap.sh <case-dir> <label> [minutes-back-for-transitions]
cd "$(dirname "$0")/.." || exit 2
D="$1"; L="$2"; M="${3:-2}"; O="$D/${L}_snap.txt"
{ echo "== $L $(date -u +%FT%T.%3NZ)"
  echo "-- pixel native"; bash docker-ws/calls28.sh pnative 2>/dev/null
  echo "-- pixel ui"; bash docker-ws/calls28.sh pui | grep -E 'Incoming|Ringing|Connected|Reconnect|Voice call|No answer|Cancelled|Missed|Declined|declined|Busy|unavailable|Unmute' | tail -3
  echo "-- iphone ui"; bash docker-ws/calls28.sh iui | grep -E 'call_status|call_row|Incoming|unavailable' | awk -F'|' '{print $2"|"$3}' | tail -2
  echo "-- pixel transitions"; /claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh .codex-test-logs/calls-20261028/pixel_logcat.txt '"event":"CALL_(STATE_TRANSITION|TERMINAL_CLEANUP_RESULT|HEADLESS_DECLINE)' 60 400 | grep -vE 'remoteIce|iceCandidate' | grep -oE '"ts":"[^"]+"|"event":"CALL_(TERMINAL|HEADLESS)[^}]+|"trigger":"[a-zA-Z]+","state":"[a-zA-Z]+","endReason":"[a-zA-Z]+"' | paste - - | tail -8
  echo "-- iphone transitions"; /claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh .codex-test-logs/calls-20261028/ios13_call_syslog4.txt 'CALL_STATE_TRANSITION|CALLKIT_DIAG\] terminal|remote_cancel' 60 400 | grep -vE 'remoteIce|iceCandidate' | grep -oE '"ts":"[^"]+"|MKNOON_[A-Z_]+\] [^"]{0,60}|"trigger":"[a-zA-Z]+","state":"[a-zA-Z]+","endReason":"[a-zA-Z]+"' | paste - - | tail -8
} > "$O" 2>&1; cat "$O"
