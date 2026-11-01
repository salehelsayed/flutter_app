#!/bin/bash
# Part A2-iOS lever: C = iPhone 13 (Appium), A = emulator-5556 (p0awsA, prod 192), B = iPhone 11 ("iphone" on iPhone 13).
#   vc196_ios_a2.sh callA <C|A> <talk-secs>   C calls A, A answers, talk, then C or A hangs up
#   vc196_ios_a2.sh callB [wait-secs]          C opens chat "iphone", reads button, taps call, reads C labels, checks B rings, C ends
#   vc196_ios_a2.sh chat <name>                C: Back to Orbit and open chat <name>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")" || exit 2
A=emulator-5556; U="bash setA_ui.sh"
C13() { (cd beta && timeout 120 python3 ap.py 13 "$@"); }
B11() { (cd beta && timeout 120 python3 ap.py 11 "$@"); }
now() { date -u +%H:%M:%S.%3N; }
CL='call_|Calling|Ringing|Connected|Reconnect|unavailable|Unavailable|Call ended|No answer|Dismiss|Couldn|could not|"End"|End call|Voice call|try again'
clabels() { C13 src "$CL" | awk -F'|' '{print $2"|"$3}' | paste -sd' ' ; }
chat() {
  C13 tap "type == 'XCUIElementTypeButton' AND label == 'Dismiss'" >/dev/null 2>&1
  C13 find "name == 'mknoon.conversation.$1'" >/dev/null 2>&1 && return 0
  C13 tap "label == 'Back'" >/dev/null 2>&1; sleep 2
  C13 tap "label == 'Open chat with $1'" >/dev/null || { echo "no chat $1"; return 3; }; sleep 3
}
awt() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do $U texts $A 2>/dev/null | grep -qE "$1" && { echo "A hit '$1' $(now)"; return 0; }; done; echo "A MISS '$1' $(now)"; return 1; }
case "$1" in
  chat) chat "$2" ;;
  callA)
    chat p0awsA || exit 3
    C13 tap "name == 'chat_call_button'" >/dev/null; echo "C dial A $(now)"
    awt 'content-desc="Answer' 50 || { echo "A did not ring; C: $(clabels)"; exit 4; }
    $U tap $A 'content-desc="Answer' >/dev/null; echo "A answered $(now)"
    awt 'Connected' 30; echo "C: $(clabels)"
    sleep "$3"; echo "talk done $(now) A: $($U texts $A | grep -E 'Call duration' )"
    if [ "$2" = C ]; then C13 tap "label == 'End' OR name == 'call_end' OR label == 'End call'" >/dev/null && echo "C hung up $(now)"
    else $U tap $A 'content-desc="End"' >/dev/null && echo "A hung up $(now)"; fi
    sleep 3; echo "C after: $(clabels)"; echo "A after: $($U texts $A | grep -E 'Call ended|Voice call|Dismiss' | paste -sd' ')" ;;
  callB)
    [ -n "$2" ] && { echo "waiting $2 s $(now)"; sleep "$2"; }
    chat iphone || exit 3
    echo "C in chat iphone $(now); call button enabled=$(C13 attr "name == 'chat_call_button'" enabled) label=$(C13 attr "name == 'chat_call_button'" label)"
    C13 tap "name == 'chat_call_button'" >/dev/null; echo "C tap call B $(now)"
    for i in 1 2; do sleep 1.5; echo "C +$i: $(clabels)"; done
    if B11 wait "name == 'call_answer' OR label == 'Answer call' OR label == 'Answer'" 40 >/dev/null; then echo "B RINGING $(now)"; else echo "B did NOT ring within 40 s $(now)"; fi
    echo "C now: $(clabels)"
    C13 tap "name == 'call_cancel' OR name == 'call_end'" >/dev/null && echo "C ended $(now)"
    sleep 4; B11 tap "type == 'XCUIElementTypeButton' AND label == 'Dismiss'" >/dev/null 2>&1
    echo "C after: $(clabels)" ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
