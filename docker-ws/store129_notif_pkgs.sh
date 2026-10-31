#!/bin/bash
# Read-only: count posted notification records per Mknoon package on one device (no titles or text).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s "${1:?serial}" shell dumpsys notification --noredact 2>/dev/null | grep -oE 'NotificationRecord\([^ ]+ pkg=[^ ]+' | grep -oE 'pkg=[^ ]+' | sort | uniq -c | grep -i mknoon
adb -s "$1" shell pm list packages | grep -i mknoon | tr -d '\r'
