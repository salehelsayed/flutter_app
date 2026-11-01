#!/bin/bash
# Caption check helper (test-only). composer <serial>: print composer text value. type <serial> <text-with-%s>: tap composer, type.
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S=$2
dump(){ timeout 15 adb -s $S shell rm -f /sdcard/u.xml; timeout 20 adb -s $S shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1; timeout 15 adb -s $S shell cat /sdcard/u.xml | tr '>' '\n'; }
case $1 in
 composer) dump | grep 'resource-id="chat_composer"' | grep -o -E ' text="[^"]*"|hint="[^"]*"' | tr '\n' ' '; echo ;;
 type) L=$(dump | grep 'resource-id="chat_composer"'|head -1); read -r a b c d <<<"$(echo "$L"|grep -o 'bounds="[^"]*"'|head -1|tr -c '0-9' ' ')"; adb -s $S shell input tap $(( (a+c)/2 )) $(( (b+d)/2 )); sleep 1; adb -s $S shell input text "$3"; sleep 1 ;;
 send) L=$(dump | grep 'resource-id="chat_send"'|head -1); read -r a b c d <<<"$(echo "$L"|grep -o 'bounds="[^"]*"'|head -1|tr -c '0-9' ' ')"; adb -s $S shell input tap $(( (a+c)/2 )) $(( (b+d)/2 )); echo "SENT $(date -u +%T)";;
esac
