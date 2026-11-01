#!/bin/bash
# Call-test lever for the 2026-10-31 P0 CALLS group: Pixel 6 (adb, UI dump text only) + one iPhone (ap.py page-source text only).
#   IP=<11|13> calls31.sh pui | pnative | ptap <substr> | ptel | pnotif | pfocus | iui | itap <predicate> | istate | now | pbat
#   calls31.sh pwait <ERE> <secs>    poll Pixel UI text until it matches; prints elapsed seconds
#   calls31.sh iwait <ERE> <secs>    poll iPhone call labels until one matches; prints elapsed seconds
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/.." || exit 2
P=${PX:-21071FDF600CSC}; I=${IP:-13}
IRE='call_|Accept|Decline|Incoming|Connected|Calling|Ringing|duration|"End"|Mute|Speaker|Voice call|unavailable|Call ended|Dismiss|Reconnect|Answer|Mknoon|mknoon|Offline|Connecting'
now() { date -u +%H:%M:%S.%3N; }
case "$1" in
  now) now ;;
  pbat) adb -s $P shell dumpsys battery | grep -E '^  (level|status|USB powered|AC powered):' | tr -s ' ' | tr '\n' ' '; echo ;;
  pui) bash docker-ws/setA_ui.sh texts $P ;;
  ptap) bash docker-ws/setA_ui.sh tap $P "$2"; now ;;
  pfocus) adb -s $P shell "dumpsys window | grep -E 'mCurrentFocus|isKeyguardShowing'" ;;
  ptel) adb -s $P shell dumpsys telecom | grep -E 'Call TC@|^ *state:|mCalls|callState|CallState' | head -12 ;;
  pnotif) adb -s $P shell dumpsys notification --noredact | grep -E 'pkg=com.mknoon.app.*channel=mknoon_call' | sed 's/^ *//' | cut -c1-200 ;;
  pnative) adb -s $P shell "dumpsys telecom | grep -E 'mCalls|Call TC@' | head -4; dumpsys audio | grep -m1 'Actual mode'; appops get com.mknoon.app RECORD_AUDIO; pidof com.mknoon.app; dumpsys notification --noredact | grep -cE 'pkg=com.mknoon.app.*channel=mknoon_call'" | sed 's/^ *//' ;;
  iui) timeout 120 python3 docker-ws/beta/ap.py $I src "$IRE" ;;
  itap) timeout 120 python3 docker-ws/beta/ap.py $I tap "$2"; now ;;
  istate) timeout 60 python3 docker-ws/beta/ap.py $I app state ;;
  pwait)
    s=$(date +%s.%N); end=$(( $(date +%s) + $3 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      if bash docker-ws/setA_ui.sh texts $P 2>/dev/null | grep -qE "$2"; then echo "PWAIT_HIT $(now) +$(awk -v a="$s" -v b="$(date +%s.%N)" "BEGIN{printf \"%.1f\", b-a}")s"; exit 0; fi
    done; echo "PWAIT_MISS $(now)"; exit 1 ;;
  iwait)
    s=$(date +%s.%N); end=$(( $(date +%s) + $3 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      if timeout 60 python3 docker-ws/beta/ap.py $I src "$IRE" 2>/dev/null | grep -qE "$2"; then echo "IWAIT_HIT $(now) +$(awk -v a="$s" -v b="$(date +%s.%N)" "BEGIN{printf \"%.1f\", b-a}")s"; exit 0; fi
    done; echo "IWAIT_MISS $(now)"; exit 1 ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
