#!/bin/bash
# Read-only: the layout of `dumpsys notification --noredact` for Mknoon records (section headers + one record).
. "$(dirname "$0")/beta_env.sh"
$ADB shell dumpsys notification --noredact > /tmp/r25_notif.txt 2>/dev/null
echo "lines $(wc -l < /tmp/r25_notif.txt)"
grep -nE "^  [A-Z][A-Za-z ]+[:(]|Notification List|Archive|Snoozed|mSnoozed|NotificationRecord\(.*mknoon" /tmp/r25_notif.txt | head -25 | cut -c1-200
N=$(grep -n "NotificationRecord(.*pkg=com.mknoon.app" /tmp/r25_notif.txt | head -1 | cut -d: -f1)
[ -n "$N" ] && sed -n "${N},$((N+45))p" /tmp/r25_notif.txt | grep -nE "NotificationRecord|channel|category|android\.(title|text|callType|callPerson)|flags|isOngoing|mImportance" | cut -c1-200
