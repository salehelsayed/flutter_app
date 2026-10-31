#!/bin/bash
# GC-003 group recovery on the Pixel receiver R. Sender S = emulator-5554 (PeerA), control C = emulator-5556 (PeerB), both on the group chat.
#   step2_gc003.sh <case: offline|background|kill|replay> <group-desc-prefix e.g. PP> <out-dir>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
CASE="$1"; G="$2"; O="$3"; R=21071FDF600CSC; S=emulator-5554; C=emulator-5556; D="$(dirname "$0")"; U="bash $D/setA_ui.sh"
mkdir -p "$O"; exec > >(tee -a "$O/$CASE.txt") 2>&1
ts() { date -u +%T; }
cnt() { $U texts "$1" | grep -c "$2"; }
open_group() { $U texts $R | grep -q 'Group information' && return; $U tap $R "Show all chats" >/dev/null; sleep 3; $U tap $R "content-desc=\"$G&#10;" >/dev/null || $U tap $R "content-desc=\"$G\"" >/dev/null; sleep 4; }
send3() { for n in 1 2 3; do echo "S send GC003_${CASE}_$n: $($U send $S GC003_${CASE}_$n)"; sleep 4; done; }
ctrl() { sleep 6; echo "control C sees: $(for n in 1 2 3; do printf '%s ' $(cnt $C GC003_${CASE}_$n); done)"; }
poll_r() { for i in $(seq 1 ${1:-24}); do X=$(for n in 1 2 3; do printf '%s ' $(cnt $R GC003_${CASE}_$n); done); [ "$X" = "1 1 1 " ] && { echo "R complete transcript at $(ts): $X"; return; }; sleep 5; done; echo "R NOT complete at $(ts): $X"; }
echo "== GC-003 $CASE start $(ts)"
case "$CASE" in
  offline)
    open_group; adb -s $R shell svc wifi disable; adb -s $R shell svc data disable; echo "R offline $(ts) (Mknoon foreground on group)"; sleep 5
    send3; ctrl; echo "dwell 60 s"; sleep 60
    echo "R rows while offline: $(for n in 1 2 3; do printf '%s ' $(cnt $R GC003_${CASE}_$n); done)"
    adb -s $R shell svc wifi enable; adb -s $R shell svc data enable; echo "R network on $(ts)"; poll_r 36 ;;
  background)
    open_group; adb -s $R shell input keyevent 3; echo "R HOME $(ts)"; sleep 5
    send3; ctrl; sleep 20
    echo "R notifications while background:"; bash $D/setA_notifs.sh $R | grep GC003 
    adb -s $R shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; echo "R foreground via launcher $(ts)"; sleep 4; open_group; poll_r 24 ;;
  kill)
    open_group; adb -s $R shell input keyevent 3; sleep 3; adb -s $R shell am kill com.mknoon.app; sleep 2
    echo "R am kill (OS-style, not force-stop) $(ts); pid now: '$(adb -s $R shell pidof com.mknoon.app)'"
    send3; ctrl; sleep 25
    echo "R pid after sends: '$(adb -s $R shell pidof com.mknoon.app)'"
    echo "R notifications while terminated:"; bash $D/setA_notifs.sh $R | grep GC003
    adb -s $R shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; echo "R relaunch via launcher $(ts)"; sleep 12; open_group; poll_r 24 ;;
  replay)
    adb -s $R shell am force-stop com.mknoon.app; adb -s $R shell am start -n com.mknoon.app/.MainActivity >/dev/null; echo "R force-stop + relaunch $(ts)"; sleep 14; open_group; sleep 5
    for c in offline background kill; do echo "R counts $c: $(for n in 1 2 3; do printf '%s ' $(cnt $R GC003_${c}_$n); done)"; done
    echo "S live: $($U send $S GC003_live)"; sleep 10; echo "R live count: $(cnt $R GC003_live) C live: $(cnt $C GC003_live)"
    echo "C control send: $($U send $C GC003_ctrl_after)"; sleep 10; echo "R: $(cnt $R GC003_ctrl_after) S: $(cnt $S GC003_ctrl_after)" ;;
esac
echo "== GC-003 $CASE end $(ts)"
