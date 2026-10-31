#!/bin/bash
# Container-side helper for the Pixel: dump UI labels with bounds, or tap the centre of the first node whose
# text or content-desc matches a regex. UI dumps only, never screenshots.
#   bash docker-ws/pixel_ui.sh dump [regex]
#   bash docker-ws/pixel_ui.sh tap <regex>
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
A="/claude-host-bin/adb -s 21071FDF600CSC"
$A shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
X=$($A shell cat /sdcard/u.xml); $A shell rm -f /sdcard/u.xml
MODE="$1" RX="${2:-.}" python3 -c '
import os,re,sys
x=sys.stdin.read(); mode=os.environ["MODE"]; rx=re.compile(os.environ["RX"])
for n in re.findall(r"<node [^>]*>", x):
    t=(re.search(r"\btext=\"([^\"]*)\"",n) or [None,""])[1]; d=(re.search(r"content-desc=\"([^\"]*)\"",n) or [None,""])[1]
    b=re.search(r"bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"",n)
    if not (t or d) or not b: continue
    if mode=="dump":
        if rx.search(t) or rx.search(d): print(repr(t[:60]), repr(d[:60]), b.group(0)[8:-1])
    elif rx.search(t) or rx.search(d):
        x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); break
' <<< "$X" > /tmp/pixel_ui.$$
if [ "$1" = tap ]; then
  read -r cx cy < /tmp/pixel_ui.$$; rm -f /tmp/pixel_ui.$$
  [ -n "${cx:-}" ] || { echo "no match"; exit 1; }
  $A shell input tap "$cx" "$cy"; echo "tapped $cx $cy"
else cat /tmp/pixel_ui.$$; rm -f /tmp/pixel_ui.$$; fi
