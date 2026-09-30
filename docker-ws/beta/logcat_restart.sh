#!/bin/bash
# Dump the emulator's current log buffers, then restart a continuous logcat
# capture in its own session (perl setsid) so the bridge cannot reap it.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
T=$(date +%H%M%S)
$ADB logcat -d -v threadtime -b main,system,crash > "$RUN/android_logcat_dump_$T.txt" 2>&1
echo "dump: $(wc -l < "$RUN/android_logcat_dump_$T.txt") lines, first: $(grep -m1 -E '^[0-9]{2}-' "$RUN/android_logcat_dump_$T.txt" | cut -c1-18)"
[ -f "$RUN/logcat.pid" ] && kill "$(cat "$RUN/logcat.pid")" 2>/dev/null
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' \
  "$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime \
  > "$RUN/android_logcat_live_$T.txt" 2>&1 < /dev/null &
sleep 1
pgrep -f "logcat -T 1 -v threadtime" | head -1 > "$RUN/logcat.pid"
echo "live capture pid $(cat "$RUN/logcat.pid") -> android_logcat_live_$T.txt"
