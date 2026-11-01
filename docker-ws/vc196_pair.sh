#!/bin/bash
# VC-026 follow-up lever (build 196): caller emulator-5554 (p0rg002) -> callee emulator-5556 (Username). UI dump text only.
#   vc196_pair.sh call <hangup|killcaller|noanswer> <talk-secs> <out>   one call leg, timeline to <out>
#   vc196_pair.sh rows <serial> <chat-name>                              open that chat and print its call rows
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
C=${CALLER:-emulator-5554}; E=${CALLEE:-emulator-5556}; U="bash setA_ui.sh"
now() { date -u +%H:%M:%S.%3N; }
wt() { local s=$1 re=$2 end=$(( $(date +%s) + $3 )); while [ "$(date +%s)" -lt "$end" ]; do $U texts $s 2>/dev/null | grep -qE "$re" && { echo "hit '$re' on $s $(now)"; return 0; }; done; echo "MISS '$re' on $s $(now)"; return 1; }
CRE='Answer|Decline|Hang up|End call|Connected|Ringing|Calling|Reconnecting|Call ended|No answer|Missed|Cancelled|Call failed|Voice call|Couldn|unavailable|Dismiss|[0-9]:[0-9][0-9]'
rows() { local s=$1 n=$2
  $U texts $s | grep -q 'Start voice call' || { $U tap $s "Open chat with $n" >/dev/null; sleep 4; }
  echo "rows $s $(now)"; $U texts $s | grep -E 'Voice call|voice call|Missed|No answer|Cancelled|Call failed|Couldn|Declined|declined|expired'; }
case "$1" in
  rows) rows "$2" "$3" ;;
  call)
    M=$2; T=$3; O=$4
    {
      $U texts $C | grep -q 'Start voice call' || { $U tap $C 'Open chat with Username' >/dev/null; sleep 4; }
      $U tap $C 'content-desc="Start voice call"' >/dev/null; echo "caller dial $(now)"
      wt $E 'content-desc="Answer' 50 || $U texts $E | grep -E "$CRE" | head -5 | sed 's/^/callee: /'
      if [ "$M" = noanswer ]; then
        wt $C 'No answer|Call ended|expired|Missed' 120
        $U texts $C | grep -E "$CRE" | head -6 | sed 's/^/caller end: /'
      else
        $U tap $E 'content-desc="Answer' >/dev/null; echo "callee answered $(now)"
        wt $C 'Connected|[0-9]:[0-9][0-9]' 30
        $U texts $C | grep -E "$CRE" | head -4 | sed 's/^/caller connected: /'
        sleep "$T"; echo "after talk $(now)"
        $U texts $C | grep -E "$CRE" | head -4 | sed 's/^/caller before end: /'
        if [ "$M" = hangup ]; then
          $U tap $C 'content-desc="End"' && echo "caller hung up $(now)"
          sleep 4
        else
          if [ "${KILL:-crash}" = home ]; then adb -s $C shell am start -W -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null; adb -s $C shell am kill com.mknoon.app; echo "KILLED caller (HOME + am kill) $(now)"
          else adb -s $C shell am crash com.mknoon.app; echo "CRASHED caller (am crash) $(now)"; fi
          sleep 2; echo "caller pid after crash: '$(adb -s $C shell pidof com.mknoon.app)'"
          wt $E 'Call ended|Call could not reconnect|Start voice call' 60
          $U texts $E | grep -E "$CRE" | head -5 | sed 's/^/callee after kill: /'
          adb -s $C shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; echo "caller relaunched $(now)"; sleep 15
          $U texts $C | grep -E "$CRE|Return to call" | sed 's/^/caller relaunch ui: /'
        fi
      fi
    } 2>&1 | tee "$O" ;;
  *) sed -n 2,4p "$0"; exit 2 ;;
esac
