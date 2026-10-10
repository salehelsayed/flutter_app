#!/bin/bash
# Post-deploy check: open Mknoon on the Pixel 6 (real installed build) so it
# reconnects to the production relay.
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
S=21071FDF600CSC
echo "Pixel 6 Mknoon: $($ADBB -s $S shell dumpsys package com.mknoon.app | grep -m1 versionName | tr -d ' \r')"
$ADBB -s $S shell input keyevent 224
$ADBB -s $S logcat -c
$ADBB -s $S shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 25
echo "pid: $($ADBB -s $S shell pidof com.mknoon.app | tr -d '\r')"
$ADBB -s $S logcat -d | grep -oE '"event":"(RELAY|NODE_START|RESERVATION|P2P_NODE)[A-Z_]*"[^}]{0,80}' | sort | uniq -c | sort -rn | head -8
