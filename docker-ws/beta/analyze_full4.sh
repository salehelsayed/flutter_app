#!/bin/bash
# Read-only summary of a run_full4.sh run. Sections (pass one or more names, default all):
#   timeline maestro rows ids pixel native procs iphone diag
# Usage: analyze_full4.sh [run dir|-] [section ...]
. "$(dirname "$0")/beta_env.sh"
RUN="${1:--}"; [ "$RUN" = - ] && RUN=$(current_run); shift
SECTIONS="${*:-timeline maestro rows ids pixel native procs iphone diag}"
want() { case " $SECTIONS " in *" $1 "*) return 0 ;; esac; return 1; }
EV='"event":"CALL_(STATE_TRANSITION|CONTROL_SIGNAL_SEND_RESULT|TERMINAL_CLEANUP_RESULT|INCOMING_PRESENTATION_RESULT|INCOMING_SIGNAL_NOT_ACCEPTED|SIGNALING_WAKE_RESULT|FOREGROUND_ADMISSION_SETTLEMENT)"'
echo "RUN $RUN"
if want timeline; then echo "=== timeline"; cat "$RUN/timeline.txt"; fi
if want maestro; then
  echo "=== maestro results (first failure line per flow)"
  for d in "$RUN"/maestro/*/; do
    f=$(grep -oE '<failure[^>]*>[^<]{0,220}' "$d/junit.xml" 2>/dev/null | head -1)
    echo "$(basename "$d"): ${f:-PASS}"
  done
fi
if want rows; then
  echo "=== call rows, voice-note labels and message texts in the UI dumps"
  for f in "$RUN"/ui/*.json; do
    echo "--- $(basename "$f")"
    grep -oE '"(accessibilityText|text)" *: *"[^"]*(Voice call|voice call|Call failed|declined|Declined|Cancelled|No answer|Voice message|Missed)[^"]*"' "$f" \
      | sed -E 's/^"[a-zA-Z]+" *: *//' | sort | uniq -c | head -14
  done
fi
if want ids; then
  echo "=== F6 identifiers seen in the UI dumps (resource-id / identifier)"
  cat "$RUN"/ui/*.json 2>/dev/null | grep -oE '"(resource-id|identifier)" *: *"(call_|chat_|message_|call_row_)[^"]*"' \
    | sed -E 's/^"[a-z-]+" *: *"//; s/"$//; s/_[0-9a-f-]{8,}.*$/_<id>/' | sort | uniq -c | head -30
fi
if want pixel; then
  echo "=== pixel call events"
  grep -E "$EV" "$RUN/android_logcat_live.txt" | grep -vE 'remoteIce|iceCandidateHandled' \
    | sed -E 's/^[0-9-]+ ([0-9:.]{12}).*"event":"/\1 /; s/","details":/ /' | cut -c1-190
fi
if want native; then
  echo "=== pixel native: headless admission (fix A), wake parse (fix C), back guard, task, errors"
  grep -E "HeadlessCallAdmission|release_deferred|WM-WorkerWrapper: Starting work for com.mknoon|Impeller opt-out|CALL_ANDROID_[A-Z_]+|MknoonCallWake|ForegroundCallBackGuard|moveTaskToBack|BridgeTeardown|handler_exception|FATAL EXCEPTION" "$RUN/android_logcat_live.txt" \
    | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +([0-9]+) +([0-9]+) ([A-Z]) /\1 p\2 t\3 \4 /' | cut -c1-210 | head -80
fi
if want procs; then
  echo "=== pixel app process starts / deaths"
  grep -E "Start proc [0-9]+:com.mknoon.app|Process com.mknoon.app .*has died|Killing [0-9]+:com.mknoon.app|am_proc_died.*com.mknoon" "$RUN/android_logcat_live.txt" | cut -c1-170
fi
if want iphone && [ -f "$RUN/ios_simulator_log.txt" ]; then
  echo "=== iphone call events"
  grep -oE '"ts":"[^"]+"[^{]*'"$EV"',"details":\{[^}]{0,170}' "$RUN/ios_simulator_log.txt" \
    | grep -vE 'remoteIce|iceCandidateHandled' \
    | sed -E 's/"ts":"2026-09-2[5-7]T([0-9:.]{12})[^"]*"[^{]*"event":"/\1 /' | cut -c1-210
fi
if want diag; then
  echo "=== pixel native call diagnostics per scenario window"
  for f in "$RUN"/diag_*.txt; do echo "--- $f"; tail -n +3 "$f" | cut -c1-200 | head -40; done
fi
