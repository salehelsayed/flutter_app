#!/bin/bash
# Part B PiP cycle on the receiver emulator-5554 (build 196). Taps More actions / Picture in Picture by the coordinates
# recorded from the viewer (a playing video makes uiautomator dumps fail), then expands via p193_pip.sh.
#   vc196_pip_cycle.sh cycle <n>     one PiP enter + expand, with state before/after and MknoonPiP / [MKNOON_PIP] lines
#   vc196_pip_cycle.sh tryonly       PiP enter only (no expand); prints whether a pinned task appeared and any snackbar
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")" || exit 2
S=emulator-5554; A() { timeout 25 adb -s $S "$@"; }; now() { date -u +%H:%M:%S.%3N; }
texts() { for i in 1 2 3; do X=$(bash setA_ui.sh texts $S 2>/dev/null | grep -v DUMP_FAILED | grep -v mCurrentFocus); [ -n "$X" ] && { echo "$X"; return; }; sleep 1; done; echo "(dump failed 3x: video playing)"; }
pipcount() { A shell dumpsys activity activities | grep -c ReceivedVideoPictureInPicture; }
enter() {
  echo "viewer before: $(texts | grep -E 'More actions|/ |Play|Pause|Picture|couldn|Couldn' | paste -sd' ')"
  A shell input tap 985 206; echo "more $(now)"; sleep 1.5
  echo "menu: $(texts | grep -E 'Picture in Picture|Delete' | paste -sd' ')"
  A shell input tap 828 983; echo "pip tapped $(now)"; sleep 1.5
  echo "after tap: $(texts | grep -iE "couldn|could not|can't|unable|picture|More actions" | paste -sd' ')"
  sleep 1.5; bash p193_pip.sh state; echo "ReceivedVideoPictureInPicture count=$(pipcount)"
}
case "$1" in
  cycle)
    echo "== cycle $2 $(now)"; enter
    bash p193_pip.sh expand; sleep 2
    bash p193_pip.sh state; echo "ReceivedVideoPictureInPicture count=$(pipcount)"
    echo "viewer after expand: $(texts | grep -E 'More actions|/ |Play|Pause' | paste -sd' ')"
    echo "-- MknoonPiP / [MKNOON_PIP] (logcat -d)"; A logcat -d -v time | grep -E 'MknoonPiP|\[MKNOON_PIP\]' | tail -25 ;;
  tryonly) echo "== try $(now)"; enter; echo "-- MknoonPiP"; A logcat -d -v time | grep -E 'MknoonPiP|\[MKNOON_PIP\]' | tail -8 ;;
  *) sed -n 2,6p "$0"; exit 2 ;;
esac
