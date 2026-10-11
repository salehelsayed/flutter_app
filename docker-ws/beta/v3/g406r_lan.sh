#!/bin/bash
# Plan 406 decision D2: short device LAN run, ~50 sends each way, Pixel 6 <-> iPhone 13 on the same Wi-Fi.
# Container-side. Both chats must already be open (Pixel: chat with iphone-13, iPhone: chat with puxel).
# Proof = sender logs CHAT_MSG_SEND_SUCCESS status delivered (recipient acked) + transport, counted afterwards.
#   g406r_lan.sh pixel N [first]   |   g406r_lan.sh iphone N [first]
. "$(dirname "$0")/lib.sh"
OUT=/workspace/artifacts/beta-20261011; mkdir -p "$OUT/ui"
N=${2:-50}; FIRST=${3:-1}
case "$1" in
  pixel)
    echo "[$(ts)] pixel: finding composer"
    p_dump lan0 >/dev/null
    b=$(grep -oE '<node [^>]*resource-id="chat_composer"[^>]*>' "$OUT/ui/lan0.xml" | grep -oE 'bounds="[^"]*"' | grep -oE '[0-9]+')
    set -- $b; padb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 )); sleep 2
    p_dump lan1 >/dev/null; padb shell input text "x"; sleep 1; p_dump lan2 >/dev/null
    s=$(grep -oE '<node [^>]*resource-id="chat_send"[^>]*>' "$OUT/ui/lan2.xml" | grep -oE 'bounds="[^"]*"' | grep -oE '[0-9]+')
    set -- $s; SX=$(( ($1 + $3) / 2 )); SY=$(( ($2 + $4) / 2 )); echo "send button at $SX,$SY"
    padb shell input keyevent KEYCODE_DEL
    for i in $(seq -w "$FIRST" "$N"); do
      if ! padb shell dumpsys input_method | grep -q 'mInputShown=true'; then  # keyboard closed: refocus the composer
        echo "[$(ts)] pixel: keyboard closed, refocusing"; padb shell input tap 540 2240; sleep 2
      fi
      padb shell input text "L406-P-$i"; sleep 0.5
      padb shell input tap $SX $SY; echo "[$(ts)] pixel sent L406-P-$i"; sleep 2
    done ;;
  iphone)
    for i in $(seq -w "$FIRST" "$N"); do
      if ! ios find "name == 'chat_composer'" >/dev/null 2>&1; then
        echo "[$(ts)] iphone: chat closed, reopening"; ios tap "label == 'Open chat with puxel'" >/dev/null; sleep 3
      fi
      if ios type "name == 'chat_composer'" "L406-I-$i" >/dev/null && ios tap "name == 'chat_send'" >/dev/null; then
        echo "[$(ts)] iphone sent L406-I-$i"
      else
        echo "[$(ts)] iphone FAILED L406-I-$i"
      fi
      sleep 1
    done ;;
esac
