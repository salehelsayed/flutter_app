#!/bin/bash
# Mknoon channel page in Android Settings. Prints only the channel switch and Mknoon/channel labels (never other Settings content).
#   notify32_channel.sh show <channel-id>     open the page and print the filtered nodes
#   notify32_channel.sh toggle <channel-id>   open the page and tap the first switch node
#   notify32_channel.sh state <channel-id>    importance of the channel from dumpsys (0 = blocked)
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
P=${PX:-21071FDF600CSC}; A() { timeout 20 adb -s $P "$@"; }
open() { A shell am start -a android.settings.CHANNEL_NOTIFICATION_SETTINGS --es android.provider.extra.APP_PACKAGE com.mknoon.app --es android.provider.extra.CHANNEL_ID "$1" >/dev/null; sleep 2.5; }
nodes() { A shell rm -f /sdcard/c.xml; A shell uiautomator dump /sdcard/c.xml >/dev/null 2>&1; A shell cat /sdcard/c.xml | tr '>' '\n' | grep -E 'class="android.widget.Switch"|checkable="true"|text="(Messages|mknoon|Mknoon|All [^"]*|Show notifications|Allow notifications)"'; A shell rm -f /sdcard/c.xml; }
case "$1" in
  show) open "$2"; nodes | grep -oE '(text|resource-id|checked)="[^"]*"|bounds="[^"]*"' | paste -sd' ' ;;
  toggle) open "$2"; L=$(nodes | grep 'resource-id="android:id/switch_widget"' | head -1); [ -z "$L" ] && { echo "NO SWITCH"; exit 3; }
    echo "before $(echo "$L" | grep -oE 'checked="[a-z]+"')"
    read -r x1 y1 x2 y2 <<<"$(echo "$L" | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' ')"; A shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )); sleep 1.5
    echo "after $(nodes | grep 'resource-id="android:id/switch_widget"' | head -1 | grep -oE 'checked="[a-z]+"') $(date -u +%T)" ;;
  state) A shell dumpsys notification | awk '/AppSettings: com.mknoon.app/{f=1} f&&/NotificationChannel\{/{print} f&&/AppSettings: /&&!/com.mknoon.app/{f=0}' | grep "mId='$2'" | grep -oE "mId='[^']*'|mImportance=[0-9-]+|mUserLockedFields=[0-9]+" | paste -sd' ' ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
