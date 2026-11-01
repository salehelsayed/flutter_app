#!/bin/bash
# Media-test lever for the 2026-10-31 P0 MEDIA group. Page-source text only (no screenshots).
#   media31.sh isrc <11|13> [ERE]   compact iPhone element lines (default: chat/media/voice labels)
#   media31.sh itap <11|13> <pred>  tap an iOS predicate match
#   media31.sh pui [ERE]            Pixel UI texts (filtered)
#   media31.sh now
#   media31.sh isend <11|13> <text>   verified text send on iPhone
#   media31.sh pick <exact text> | pfocus   picker-safe Pixel tap (prints nothing from the picker) / focused activity
#   media31.sh idel <11|13> <pred> | pdel <substr>   delete own test message for everyone
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/.." || exit 2
P=${PX:-21071FDF600CSC}
MRE='chat_|message_|voice|Voice|Play|Pause|Photo|photo|Video|video|Image|image|caption|Send|Delete|delete|Download|download|Media|media|Document|document|Camera|camera|Record|record|Cancel|Discard|Keep|Sending|Sent|Received|Failed|Retry|Upload|upload|Processing|Open|Save|Share|Forward|Private|private|Protected|Allow|Settings|seconds|0:0|pdf|PDF|P0|p0'
case "$1" in
  now) date -u +%H:%M:%S ;;
  isrc) timeout 120 python3 docker-ws/beta/ap.py "$2" src "${3:-$MRE}" | awk -F'|' '{print $1"|"$2"|"$3"|"$4"|"$5}' ;;
  itap) timeout 120 python3 docker-ws/beta/ap.py "$2" tap "$3"; date -u +%T ;;
  pui) bash docker-ws/setA_ui.sh texts $P | grep -E "${2:-.}" ;;
  idel) # idel <11|13> <predicate of own message bubble>: long-press -> Delete -> Delete for Everyone
    timeout 120 python3 docker-ws/beta/ap.py "$2" hold "$3" 900 || exit 3; sleep 1.5
    timeout 120 python3 docker-ws/beta/ap.py "$2" tap "name == 'message-context-delete-action'" || exit 4; sleep 1.5
    timeout 120 python3 docker-ws/beta/ap.py "$2" tap "name == 'conversation-delete-for-everyone-action'" || exit 5; echo "deleted for everyone $(date -u +%T)" ;;
  pdel) # pdel <substring of own message content-desc>: long-press -> Delete -> Delete for Everyone (Pixel)
    L=$(adb -s $P shell rm -f /sdcard/u.xml; adb -s $P shell uiautomator dump /sdcard/u.xml >/dev/null; adb -s $P shell cat /sdcard/u.xml | tr '>' '\n' | grep -F -- "$2" | head -1)
    [ -z "$L" ] && { echo "NOT FOUND: $2"; exit 3; }
    read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"
    adb -s $P shell input swipe $(( (x1+x2)/2 )) $(( (y1+y2)/2 )) $(( (x1+x2)/2 )) $(( (y1+y2)/2 )) 900; sleep 1.5
    bash docker-ws/setA_ui.sh tap $P 'Delete' || exit 4; sleep 1.5
    bash docker-ws/setA_ui.sh tap $P 'Delete for Everyone' || exit 5; echo "deleted for everyone $(date -u +%T)" ;;
  isend) # isend <11|13> <text>: type into chat_composer, verify the value, then send (refuses to send a garbled text)
    for try in 1 2 3; do
      timeout 120 python3 docker-ws/beta/ap.py "$2" tap "name == 'chat_composer'" >/dev/null; sleep 1
      timeout 120 python3 docker-ws/beta/ap.py "$2" key "$3" >/dev/null; sleep 1
      V=$(timeout 120 python3 docker-ws/beta/ap.py "$2" attr "name == 'chat_composer'" value)
      [ "$V" = "$3" ] && { timeout 120 python3 docker-ws/beta/ap.py "$2" tap "name == 'chat_send'" >/dev/null; echo "sent '$3' $(date -u +%T)"; exit 0; }
      (cd docker-ws/beta && timeout 120 python3 -c "import sys; sys.argv=['ap.py']; import ap; s=ap.sid('$2'); e=ap.el('$2', \"name == 'chat_composer'\"); ap.req('POST', f'/session/{s}/element/{e}/clear', {})") >/dev/null 2>&1
      echo "value mismatch ('$V'), retry $try"
    done; echo "NOT SENT '$3'"; exit 4 ;;
  pick) # pick <exact text or content-desc>: picker-safe tap (prints only tapped/NOT FOUND, never the picker contents)
    L=$(adb -s $P shell rm -f /sdcard/u.xml; adb -s $P shell uiautomator dump /sdcard/u.xml >/dev/null; adb -s $P shell cat /sdcard/u.xml | tr '>' '\n' | grep -E "(text|content-desc)=\"$2\"" | head -1)
    [ -z "$L" ] && { echo "NOT FOUND: $2"; exit 3; }
    read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"
    adb -s $P shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); echo "tapped $2" ;;
  pfocus) adb -s $P shell dumpsys window | grep mCurrentFocus | grep -oE '[a-zA-Z.]+/[a-zA-Z.]+' ;;
  *) sed -n 2,8p "$0"; exit 2 ;;
esac
