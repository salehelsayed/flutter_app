#!/bin/bash
# Read-only: one NotificationRecord from the Pixel's notification list, to see how title/text/category print.
. "$(dirname "$0")/beta_env.sh"
$ADB shell dumpsys notification --noredact > /tmp/r25_notif.txt 2>/dev/null
N=$(grep -n "NotificationRecord(" /tmp/r25_notif.txt | head -1 | cut -d: -f1)
sed -n "${N},$((N+60))p" /tmp/r25_notif.txt | grep -nE "NotificationRecord|pkg=|channel|category|android\.(title|text|callType|callPerson)|flags=|extras|mImportance" | cut -c1-180 | head -20
