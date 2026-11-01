#!/bin/bash
# VC-026 Android legs (emulator-5554 <-> iPhone 11). The EMULATOR is always the killed side (am crash).
#   p193_vc026a.sh run <emu-caller|emu-callee> <ring|active> <out>
#   p193_vc026a.sh erows                     open the emulator chat "iphone" and print its call rows
#   p193_vc026a.sh irows                     open the iPhone 11 chat "p0rg002" and print its call rows
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")" || exit 2
S=emulator-5554; U="bash setA_ui.sh"
AP() { (cd beta && timeout 120 python3 ap.py 11 "$@"); }
now() { date -u +%H:%M:%S.%3N; }
ewait() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do $U texts $S 2>/dev/null | grep -qE "$1" && { echo "ewait hit '$1' $(now)"; return 0; }; done; echo "ewait MISS '$1' $(now)"; return 1; }
CRE='Answer|Decline|Hang up|End call|Connected|Ringing|Calling|Reconnecting|Call ended|No answer|Missed|Cancelled|Call failed|Voice call|Couldn|microphone|Dismiss'
erows() {
  $U texts $S | grep -q 'Start voice call' || { $U tap $S 'Open chat with iphone' >/dev/null || $U tap $S 'content-desc="iphone' >/dev/null; sleep 4; }
  echo "emu rows $(now)"; $U texts $S | grep -E 'Voice call|Missed|No answer|Cancelled|Call failed|Couldn|Declined|voice call'
}
irows() {
  AP tap "type == 'XCUIElementTypeButton' AND label == 'Dismiss'" >/dev/null 2>&1
  AP find "name == 'chat_composer'" >/dev/null 2>&1 || { AP tap "label BEGINSWITH 'Open chat with p0rg002'" >/dev/null; sleep 4; }
  echo "ip11 rows $(now)"; AP src 'call_row_' | awk -F'|' '{print $2"|"$3}'
}
case "$1" in
  erows) erows ;;
  irows) irows ;;
  run)
    R=$2; MODE=$3; O=$4
    {
      if [ "$R" = emu-caller ]; then
        $U tap $S 'Start voice call' >/dev/null; echo "emu dial $(now)"
        AP wait "name == 'call_answer' OR label == 'Answer call'" 45 && echo "ip11 ringing $(now)"
        if [ "$MODE" = active ]; then AP tap "name == 'call_answer' OR label == 'Answer call'" >/dev/null; echo "ip11 answered $(now)"; ewait 'Connected|[0-9]:[0-9][0-9]' 30; sleep 8; else sleep 2; fi
      else
        AP tap "name == 'chat_call_button'" >/dev/null; echo "ip11 dial $(now)"
        ewait 'Answer' 45
        if [ "$MODE" = active ]; then $U tap $S 'content-desc="Answer' >/dev/null || $U tap $S 'Answer' >/dev/null; echo "emu answered $(now)"; AP wait "label == 'Connected'" 30 && echo "ip11 connected $(now)"; sleep 8; else sleep 2; fi
      fi
      $U texts $S | grep -E "$CRE" | head -5 | sed 's/^/emu before kill: /'
      adb -s $S shell am crash com.mknoon.app; echo "CRASHED emu ($R, $MODE) $(now)"
      sleep 2; echo "emu pid after crash: '$(adb -s $S shell pidof com.mknoon.app)'"
      for i in $(seq 1 15); do sleep 5
        L=$(AP src 'call_status|call_answer|Answer call|Call ended|Dismiss' | awk -F'|' '{print $2"|"$3}' | paste -sd' ')
        echo "$(now) survivor ip11: $L"
        echo "$L" | grep -q 'Call ended' && break; echo "$L" | grep -qE 'call_status|call_answer|Answer call' || break
      done
      echo "survivor clear $(now)"
      adb -s $S shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; echo "emu relaunched $(now)"; sleep 15
      $U texts $S | grep -E "$CRE|Return to call" | sed 's/^/emu relaunch ui: /'
    } 2>&1 | tee "$O" ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
