#!/bin/bash
# Pixel: print attribute names and value lengths of EditText nodes on screen (values not printed).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
adb -s $S shell uiautomator dump /sdcard/u.xml >/dev/null 2>&1
adb -s $S shell cat /sdcard/u.xml | python3 -c '
import sys,re
x=sys.stdin.read()
for m in re.finditer(r"<node[^>]*EditText[^>]*>", x):
    print([(k,len(v)) for k,v in re.findall(r"([a-z-]+)=\"([^\"]*)\"", m.group(0)) if v])'
adb -s $S shell dumpsys window | grep mCurrentFocus
