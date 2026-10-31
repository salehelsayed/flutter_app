#!/bin/bash
# Pixel call-notification driver (UI dump only, never a screenshot):
#   callfix_notif_action.sh wait <secs>          poll dumpsys notification until a com.mknoon.app category=call record exists
#   callfix_notif_action.sh tap <label> [shade]  dump (optionally after expanding the shade) and tap the first node whose
#                                                text or content-desc equals <label>; collapses the shade afterwards
#   callfix_notif_action.sh dump [shade]         print text/content-desc of the current (or shade) UI
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S=21071FDF600CSC
now() { date -u +%H:%M:%S.%3N; }
dumpui() {
  [ "${1:-}" = shade ] && { adb -s $S shell cmd statusbar expand-notifications; sleep 1; }
  adb -s $S shell 'uiautomator dump /sdcard/cf.xml >/dev/null 2>&1; cat /sdcard/cf.xml' | tr '>' '\n'
}
case "$1" in
  wait)
    end=$(( $(date +%s) + ${2:-40} ))
    while [ "$(date +%s)" -lt "$end" ]; do
      if adb -s $S shell dumpsys notification --noredact | grep -E 'pkg=com.mknoon.app.*channel=mknoon_call' | grep -q 'category=call'; then
        echo "CALL_NOTIF $(now)"; exit 0; fi
      sleep 0.5
    done; echo "CALL_NOTIF_MISS $(now)"; exit 1 ;;
  dump) dumpui "${2:-}" | grep -o -E '(content-desc|text)="[^"]{1,80}"' | grep -v '=""'
    [ "${2:-}" = shade ] && adb -s $S shell cmd statusbar collapse ;;
  tap)
    X=$(dumpui "${3:-}"); B=$(echo "$X" | grep -E "(text|content-desc)=\"$2\"" | head -1 | grep -o 'bounds="[^"]*"' | head -1)
    if [ -z "$B" ]; then echo "NOT FOUND: $2 $(now)"; echo "$X" | grep -o -E '(content-desc|text)="[^"]{1,60}"' | grep -v '=""' | head -20
      [ "${3:-}" = shade ] && adb -s $S shell cmd statusbar collapse; exit 3; fi
    read x1 y1 x2 y2 <<<"$(echo "$B" | tr -c '0-9' ' ')"
    adb -s $S shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))
    echo "tapped $2 at $(( (x1+x2)/2 )),$(( (y1+y2)/2 )) $(now)" ;;
  *) sed -n 2,6p "$0"; exit 2 ;;
esac
