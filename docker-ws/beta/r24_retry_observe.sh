#!/bin/bash
# Tap the snackbar Retry (at its UI-tree bounds centre) and record what follows: UI nodes + screenshots at
# +4 s, +30 s, +90 s, +180 s, and the app's retry/media events from the live logcat.
. "$(dirname "$0")/beta_env.sh"
H="$(cd "$(dirname "$0")" && pwd)"
RUN=$(current_run)
t0=$($ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r')
echo "tap Retry at emulator $t0"
$ADB shell input tap 942 2274
for s in 4 30 90 180; do
  sleep $([ $s = 4 ] && echo 4 || echo $(( s - prev )) ); prev=$s
  echo "=== +${s}s"
  bash "$H/r24_ui.sh" "retry_${s}s" | tail -6
  bash "$H/r24_snap.sh" "retry_${s}s" | head -1
done
echo "=== app events since the tap"
awk -v s="$t0" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" | grep -oE '"event":"[A-Z_]*(RETRY|VIDEO|MEDIA_PROC|PROCESS|UNAVAILABLE|PENDING)[A-Z_]*"[^}]*' | sort | uniq -c | head -12
awk -v s="$t0" '($1 " " substr($2,1,8)) >= s' "$RUN/android_logcat_live.txt" | grep -iE "StateError|Already have a compression|VideoCompress" | head -5 | cut -c1-240
echo "RETRY OBSERVE DONE"
