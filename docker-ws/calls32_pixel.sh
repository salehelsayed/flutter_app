#!/bin/bash
# Pixel helpers for the 2026-11-01 P0 Pixel legs. System-surface output is filtered to Mknoon/call lines before it is printed.
#   calls32_pixel.sh shade                 expand the shade, print only Mknoon call nodes (Answer/Decline/Mknoon/iphone/Incoming)
#   calls32_pixel.sh shadetap <text>        expand the shade and tap the first Mknoon call node whose text/desc equals <text>
#   calls32_pixel.sh collapse              collapse the shade
#   calls32_pixel.sh mic                   mic probe: audio recording clients, RECORD_AUDIO appops, audio mode (com.mknoon.app only)
#   calls32_pixel.sh notifs                Mknoon notification records only (channel, flags), no text
#   calls32_pixel.sh channels              Mknoon notification channels with importance
#   calls32_pixel.sh home                  HOME intent (app to background)
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
P=${PX:-21071FDF600CSC}; A() { timeout 20 adb -s $P "$@"; }
KEEP='(text|content-desc)="(Answer|Decline|Hang up|Mknoon|mknoon|Incoming[^"]*|iphone[^"]*|Ongoing[^"]*|Voice call[^"]*)"'
sdump() { A shell rm -f /sdcard/s.xml; A shell uiautomator dump /sdcard/s.xml >/dev/null 2>&1; A shell cat /sdcard/s.xml 2>/dev/null | tr '>' '\n' | grep -E "$KEEP"; A shell rm -f /sdcard/s.xml; }
case "$1" in
  shade) A shell cmd statusbar expand-notifications; sleep 1.5; sdump | grep -oE "$KEEP|bounds=\"[^\"]*\"" | paste -sd' ' | sed 's/bounds=/\n  bounds=/g' ;;
  shadetap)
    A shell cmd statusbar expand-notifications; sleep 1.5
    L=$(sdump | grep -E "(text|content-desc)=\"$2\"" | head -1); [ -z "$L" ] && { echo "NOT FOUND: $2 $(date -u +%T.%3N)"; exit 3; }
    read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')"
    A shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); echo "shade tapped $2 $(date -u +%T.%3N)" ;;
  collapse) A shell cmd statusbar collapse ;;
  mic)
    U=11850
    echo "-- recording events/configs for uid $U (dumpsys audio, last 6)"; A shell dumpsys audio | grep -E "riid|rec (start|stop|update|release)|RecordingConfiguration|silenced" | grep -E "$U|com.mknoon" | tail -6
    echo "-- audio_flinger input clients for uid $U"; A shell dumpsys media.audio_flinger | grep -E "^ *(Input thread|Client|Session|Track|  *[0-9]+ +[0-9]+ +$U)" | grep -E "Input thread| $U " | head -6
    echo "-- appops RECORD_AUDIO"; A shell cmd appops get com.mknoon.app RECORD_AUDIO
    echo "-- mode"; A shell dumpsys audio | grep -m1 'Actual mode' ;;
  notifs) A shell dumpsys notification --noredact | grep -E '^ *NotificationRecord.*pkg=com.mknoon.app' | grep -oE 'channel=[a-z_0-9]+|id=[0-9]+ ' | paste - - ;;
  channels) A shell dumpsys notification | awk '/AppSettings: com.mknoon.app/{f=1} f&&/NotificationChannel\{/{print} f&&/AppSettings: /&&!/com.mknoon.app/{f=0}' | grep -oE "mId='[^']*'|mImportance=[0-9-]+|mName=[^,]*" | paste - - - ;;
  home) A shell am start -W -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null; echo "home $(date -u +%T.%3N)" ;;
  *) sed -n 2,9p "$0"; exit 2 ;;
esac
