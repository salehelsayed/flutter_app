#!/bin/bash
# Endpoint-repair regression lever (build 197, Hetzner): C = emulator-5558 (p0mem6), A = emulator-5556 ("Username"), B = Pixel 6 (puxel). UI dump text only.
#   vc197_endpoint.sh callA <C|A> <talk-secs>   C calls A, A answers, talk, C or A hangs up
#   vc197_endpoint.sh callB <talk-secs>         C opens chat puxel, taps call, B answers, talk, C hangs up
#   vc197_endpoint.sh rows <serial> <chat-name> print the call rows of that chat
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
C=emulator-5558; A=emulator-5556; B=21071FDF600CSC; U="bash setA_ui.sh"
now() { date -u +%H:%M:%S.%3N; }
CRE='Answer|Decline|End|Connected|Ringing|Calling|Reconnecting|Call ended|No answer|Couldn|unavailable|Unavailable|Cancel|Start voice call|try again'
wt() { local s=$1 re=$2 end=$(( $(date +%s) + $3 )); while [ "$(date +%s)" -lt "$end" ]; do $U texts $s 2>/dev/null | grep -qE "$re" && { echo "hit '$re' on $s $(now)"; return 0; }; done; echo "MISS '$re' on $s $(now)"; return 1; }
btn() { timeout 20 adb -s $C shell 'uiautomator dump /sdcard/u.xml >/dev/null; cat /sdcard/u.xml' | tr '>' '\n' | grep -E 'content-desc="(Start voice call|Voice calling is unavailable[^"]*)"' | grep -oE 'content-desc="[^"]*"|enabled="[a-z]+"' | paste -sd' '; }
unav() { $U texts $1 | grep -c 'unavailable'; }
chat() { $U tap $C 'content-desc="Dismiss"' >/dev/null 2>&1
  $U texts $C | grep -q "View contact profile&#10;$1&#10;" && return 0
  $U tap $C 'content-desc="Back"' >/dev/null 2>&1; sleep 3; $U tap $C "Open chat with $1" >/dev/null || { echo "no chat $1"; return 3; }; sleep 3; }
talk() { local callee=$1 t=$2 who=$3
  wt $C 'Connected|[0-9]:[0-9][0-9]' 30; sleep "$t"; echo "talk done $(now) C: $($U texts $C | grep -E 'Call duration|Connected|[0-9]:[0-9][0-9]' | head -2 | paste -sd' ')"
  if [ "$who" = C ]; then $U tap $C 'content-desc="End"' >/dev/null && echo "C hung up $(now)"; else $U tap $callee 'content-desc="End"' >/dev/null && echo "callee hung up $(now)"; fi
  sleep 3; echo "C after: $($U texts $C | grep -E "$CRE" | paste -sd' ') | unavailable_count=$(unav $C)"; }
case "$1" in
  callA)
    chat Username || exit 3
    echo "C button (A chat) $(now): $(btn)"
    $U tap $C 'content-desc="Start voice call"' >/dev/null; T0=$(date +%s.%N); echo "C dial A $(now)"
    sleep 1; echo "C +1: $($U texts $C | grep -E "$CRE" | paste -sd' ')"
    wt $A 'content-desc="Answer' 50 || exit 4; echo "ring_secs=$(python3 -c "import time;print(round(time.time()-$T0,1))")"
    $U tap $A 'content-desc="Answer' >/dev/null; echo "A answered $(now)"
    talk $A "$3" "$2" ;;
  callB)
    chat puxel || exit 3
    echo "C button (B chat) $(now): $(btn)"
    $U tap $C 'content-desc="Start voice call"' >/dev/null; T0=$(date +%s.%N); echo "C tap call B $(now)"
    sleep 1; echo "C +1: $($U texts $C | grep -E "$CRE" | paste -sd' ') | unavailable_count=$(unav $C)"
    wt $B 'content-desc="Answer|text="Answer' 40 || { echo "B did NOT ring; C: $($U texts $C | grep -E "$CRE" | paste -sd' ')"; exit 5; }
    echo "B RINGING ring_secs=$(python3 -c "import time;print(round(time.time()-$T0,1))")"
    $U tap $B 'Answer' >/dev/null; echo "B answered $(now)"
    talk $B "$2" C ;;
  rows) $U texts "$2" | grep -q 'Start voice call' || { $U tap "$2" "Open chat with $3" >/dev/null; sleep 4; }
    echo "rows $2 $3 $(now)"; $U texts "$2" | grep -iE 'voice call|Missed|No answer|Cancelled|Call failed|Couldn|Declined|minute|sec|[0-9]:[0-9][0-9]' ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
