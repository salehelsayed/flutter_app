#!/bin/bash
# Stop the detached phone log captures started by start_phone_log_captures.sh.
PIXEL_SERIAL=21071FDF600CSC
echo "before:"; pgrep -fl 'idevicesyslog' || echo "  (no idevicesyslog)"; pgrep -fl "adb -s $PIXEL_SERIAL logcat" || echo "  (no logcat)"
pkill -f 'idevicesyslog' 2>/dev/null
pkill -f "adb -s $PIXEL_SERIAL logcat" 2>/dev/null
sleep 2
echo "after:"; pgrep -fl 'idevicesyslog' || echo "  (no idevicesyslog)"; pgrep -fl "adb -s $PIXEL_SERIAL logcat" || echo "  (no logcat)"
