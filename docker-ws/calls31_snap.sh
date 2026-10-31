#!/bin/bash
# Snapshot after a call step: Pixel native state + call UI rows, iPhone call labels, iPhone recent call transitions/CallKit diag.
#   IP=<11|13> calls31_snap.sh <case-dir> <label>
cd "$(dirname "$0")/.." || exit 2
D="$1"; L="$2"; I=${IP:-13}; O="$D/${L}_snap.txt"; mkdir -p "$D"
{ echo "== $L $(date -u +%FT%T.%3NZ) iphone=$I"
  echo "-- pixel native (mCalls / audio mode / RECORD_AUDIO appops / pid / mknoon_call notifications)"; bash docker-ws/calls31.sh pnative 2>/dev/null
  echo "-- pixel ui"; bash docker-ws/calls31.sh pui | grep -E 'mCurrentFocus|Incoming|Ringing|Calling|Connected|Reconnect|Voice call|No answer|Cancelled|Missed|Declined|declined|Busy|unavailable|Mute|Unmute|duration|Call ended' | grep -v 'View contact' | tail -6
  echo "-- iphone ui"; IP=$I bash docker-ws/calls31.sh iui | grep -E 'call_|Incoming|unavailable|Voice call|Missed|No answer|Cancel|declined' | awk -F'|' '{print $2"|"$3"|"$4}' | tail -6
  echo "-- iphone transitions"; /claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh .codex-test-logs/p0-phone-20261031/calls/ios${I}_syslog.txt 'CALL_STATE_TRANSITION|CALL_TERMINAL_CLEANUP|CALLKIT_DIAG\] (terminal|result)|remote_cancel' 12 500 | grep -vE 'remoteIce|iceCandidate' | grep -oE '"ts":"[^"]+"|MKNOON_[A-Z_]+\] [^"]{0,60}|"event":"CALL_TERMINAL_CLEANUP_RESULT","details":\{[^}]{0,80}|"trigger":"[a-zA-Z]+","state":"[a-zA-Z]+","endReason":"[a-zA-Z]+"' | paste - - | tail -10
} > "$O" 2>&1; cat "$O"
