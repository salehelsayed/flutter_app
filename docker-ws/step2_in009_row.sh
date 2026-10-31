#!/bin/bash
# IN-009 one row: offline Pass with process kill and restart. I = Pixel (on its chat list), passer/other = emulators on their Intros tab.
#   step2_in009_row.sh <row-label> <passer-serial> <other-serial> <out-dir>
# Sequence: I, other and passer offline (svc wifi+data) -> passer taps Pass -> force-stop passer -> relaunch -> passer
# network on -> wait for the outbox retrier -> I and other network on -> poll other's Intros and I's log for convergence.
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
R="$1"; PS="$2"; OS="$3"; O="$4"; I=21071FDF600CSC; D="$(dirname "$0")"; U="bash $D/setA_ui.sh"
mkdir -p "$O"; exec > >(tee -a "$O/$R.txt") 2>&1
ts() { date -u +%T; }
net() { adb -s "$1" shell svc wifi "$2"; adb -s "$1" shell svc data "$2"; }
logs() { adb -s "$1" logcat -d 2>/dev/null | grep -F "\"event\":\"$2\"" | tail -${3:-3} | grep -oE '^[0-9-]+ [0-9:.]+|"details":\{[^}]{0,160}' | paste - - ; }
intros() { $U texts "$1" | grep -E 'Introduced by|"Pass"|"Accept"|Intros|No introductions' | tr '\n' ' '; echo; }
echo "== $R start $(ts) passer=$PS other=$OS"
echo "passer intros: $(intros $PS)"; echo "other intros: $(intros $OS)"
net $I disable; net $OS disable; net $PS disable; echo "offline I+other+passer $(ts)"; sleep 6
adb -s $PS shell dumpsys connectivity | grep -m1 'Active default network' 
$U tap $PS 'content-desc="Pass"' && echo "PASS tapped $(ts)"; sleep 6
echo "PASS_INTRO_DONE: $(logs $PS PASS_INTRO_DONE 1)"
echo "passer intros after pass: $(intros $PS)"
adb -s $PS shell am force-stop com.mknoon.app; echo "force-stop passer $(ts)"; sleep 3
adb -s $PS shell am start -n com.mknoon.app/.MainActivity >/dev/null; echo "relaunch passer $(ts)"; sleep 14
$U tap $PS "Show all chats" >/dev/null; sleep 3; $U tap $PS 'content-desc="Intros' >/dev/null; sleep 3
echo "passer intros after restart: $(intros $PS)"
N0=$(adb -s $PS logcat -d | grep -c PENDING_RETRIER_INTRO_OUTBOX_RETRIED)
net $PS enable; echo "passer network on $(ts)"
L=""; for i in $(seq 1 30); do sleep 5; [ "$(adb -s $PS logcat -d | grep -c PENDING_RETRIER_INTRO_OUTBOX_RETRIED)" -gt "$N0" ] && { L=$(logs $PS PENDING_RETRIER_INTRO_OUTBOX_RETRIED 1); break; }; done
echo "retrier: ${L:-none after 150 s} ($(ts))"
net $I enable; net $OS enable; echo "I+other network on $(ts)"
for i in $(seq 1 36); do sleep 5; X=$(intros $OS); echo "$X" | grep -q '"Pass"' || break; done
echo "other intros at $(ts): $X"
sleep 10
echo "I STATUS_UPDATED: $(logs $I HANDLE_INCOMING_INTRO_STATUS_UPDATED 2)"
echo "other STATUS_UPDATED: $(logs $OS HANDLE_INCOMING_INTRO_STATUS_UPDATED 2)"
echo "== $R end $(ts)"
