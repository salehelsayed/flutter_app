#!/bin/bash
# VC-026 lever for the build-193 proofs (iPhone 11 <-> iPhone 13). Page-source text only.
#   p193_vc026.sh rows <11|13> <chat-name>        open the chat with <chat-name> (from Orbit or a chat) and print call rows
#   p193_vc026.sh run <caller> <callee> <ring|active> <caller|callee> <out>
#        caller dials, callee answers (active only), the chosen side is terminated (ring: once the callee rings;
#        active: 8 s after Connected), then the surviving side is polled every ~8 s until no call UI is left (max 90 s).
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/beta" || exit 2
AP() { timeout 120 python3 ap.py "$@"; }
now() { date -u +%H:%M:%S.%3N; }
CRE='call_status|call_answer|Answer call|Call ended|Reconnecting|Ringing|Calling|Connected|No answer|Dismiss'
case "$1" in
  rows)
    AP "$2" tap "type == 'XCUIElementTypeButton' AND label == 'Dismiss'" >/dev/null 2>&1
    if ! AP "$2" find "name == 'chat_composer'" >/dev/null 2>&1; then
      AP "$2" tap "label == 'Open chat with $3'" >/dev/null || { echo "NO CHAT $3"; exit 3; }; sleep 4
    fi
    echo "rows $2 $(now)"; AP "$2" src 'call_row_' | awk -F'|' '{print $2"|"$3}' ;;
  run)
    C=$2; R=$3; MODE=$4; K=$5; O=$6
    [ "$K" = caller ] && KP=$C || KP=$R; [ "$K" = caller ] && SP=$R || SP=$C
    {
      AP $C tap "name == 'chat_call_button'" >/dev/null; echo "dial $C->$R $(now)"
      AP $R wait "name == 'call_answer' OR label == 'Answer call'" 45 && echo "callee ringing $(now)"
      if [ "$MODE" = active ]; then
        AP $R tap "name == 'call_answer' OR label == 'Answer call'" >/dev/null; echo "answered $(now)"
        AP $C wait "label == 'Connected'" 30 && echo "caller connected $(now)"
        sleep 8; AP $SP src 'call_status|Call duration' | head -2
      else
        sleep 2
      fi
      AP $KP app terminate com.mknoon.app >/dev/null; echo "TERMINATED $KP ($K, $MODE) $(now)"
      for i in $(seq 1 15); do sleep 5
        L=$(AP $SP src "$CRE" | awk -F'|' '{print $2"|"$3}' | paste -sd' ')
        echo "$(now) survivor $SP: $L"
        echo "$L" | grep -q 'Call ended' && break; echo "$L" | grep -qE 'call_status|call_answer|Answer call' || break
      done
      echo "survivor clear $(now)"
      AP $KP app activate com.mknoon.app >/dev/null; echo "relaunched $KP $(now)"; sleep 10
      AP $KP src "$CRE|Return to call" | awk -F'|' '{print "relaunch ui: "$2"|"$3}'
    } 2>&1 | tee "$O" ;;
  *) sed -n 2,6p "$0"; exit 2 ;;
esac
