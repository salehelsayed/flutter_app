#!/bin/bash
# Part A2 emulator leg (build 196, Hetzner): C = emulator-5554 (p0rg002), A = emulator-5556 (p0hetA), B = Pixel 6 (puxel). UI dump text only.
#   vc196_emu_a2.sh callA <C|A> <talk-secs>   C calls A, A answers, talk, C or A hangs up
#   vc196_emu_a2.sh callB [wait-secs]          C opens chat puxel, taps call, reads C texts, checks B rings, C cancels
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
C=emulator-5554; A=emulator-5556; B=21071FDF600CSC; U="bash setA_ui.sh"
now() { date -u +%H:%M:%S.%3N; }
CRE='Answer|Decline|End|Connected|Ringing|Calling|Reconnecting|Call ended|No answer|Couldn|unavailable|Unavailable|Dismiss|Cancel|Start voice call|try again'
wt() { local s=$1 re=$2 end=$(( $(date +%s) + $3 )); while [ "$(date +%s)" -lt "$end" ]; do $U texts $s 2>/dev/null | grep -qE "$re" && { echo "hit '$re' on $s $(now)"; return 0; }; done; echo "MISS '$re' on $s $(now)"; return 1; }
chat() { $U tap $C 'content-desc="Dismiss"' >/dev/null 2>&1
  $U texts $C | grep -q "View contact profile&#10;$1&#10;" && return 0
  $U tap $C 'content-desc="Back"' >/dev/null 2>&1; sleep 3; $U tap $C "Open chat with $1" >/dev/null || { echo "no chat $1"; return 3; }; sleep 3; }
case "$1" in
  callA)
    chat p0hetA || exit 3
    $U tap $C 'content-desc="Start voice call"' >/dev/null; echo "C dial A $(now)"
    wt $A 'content-desc="Answer' 50 || exit 4
    $U tap $A 'content-desc="Answer' >/dev/null; echo "A answered $(now)"
    wt $C 'Connected' 30; sleep "$3"; echo "talk done $(now) C: $($U texts $C | grep -E 'Call duration')"
    if [ "$2" = C ]; then $U tap $C 'content-desc="End"' >/dev/null && echo "C hung up $(now)"; else $U tap $A 'content-desc="End"' >/dev/null && echo "A hung up $(now)"; fi
    sleep 2; echo "C after: $($U texts $C | grep -E "$CRE" | paste -sd' ')" ;;
  callB)
    [ -n "$2" ] && { echo "waiting $2 s $(now)"; sleep "$2"; }
    chat puxel || exit 3
    L=$(timeout 20 adb -s $C shell 'uiautomator dump /sdcard/u.xml >/dev/null; cat /sdcard/u.xml' | tr '>' '\n' | grep 'content-desc="Start voice call"' | grep -oE 'enabled="[a-z]+"|clickable="[a-z]+"' | paste -sd' ')
    echo "C in chat puxel $(now); call button: $L"
    $U tap $C 'content-desc="Start voice call"' >/dev/null; echo "C tap call B $(now)"
    for i in 1 2; do echo "C +$i: $($U texts $C | grep -E "$CRE" | paste -sd' ')"; done
    wt $B 'content-desc="Answer|text="Answer|Incoming' 40 && echo "B RINGING" || echo "B did NOT ring"
    echo "C now: $($U texts $C | grep -E "$CRE" | paste -sd' ')"
    $U tap $C 'Cancel' >/dev/null || $U tap $C 'content-desc="End"' >/dev/null; echo "C cancelled $(now)"
    sleep 4; $U tap $C 'content-desc="Dismiss"' >/dev/null 2>&1; $U tap $B 'content-desc="Dismiss"' >/dev/null 2>&1
    echo "C after: $($U texts $C | grep -E "$CRE" | paste -sd' ')" ;;
  *) sed -n 2,4p "$0"; exit 2 ;;
esac
