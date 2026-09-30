#!/bin/bash
# Self-test for gates.sh: short live logcat into a scratch run dir, then one gate pass.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
RUN="$BETA/gate-selftest-$(date '+%H%M%S')"; mkdir -p "$RUN"
. "$H/gates.sh"
"$ANDROID_HOME/platform-tools/adb" -s "$SERIAL" logcat -T 1 -v threadtime > "$RUN/android_logcat_live.txt" 2>&1 &
LC=$!
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 20
echo "emu_skew: $(emu_skew)"
echo "host_load: $(host_load)"
echo "app_quiet_s: $(app_quiet_s)"
touch "$RUN/timeline.txt"
gate selftest
cat "$RUN/timeline.txt"
echo "ping lines seen:"; grep -cE '"event":"P2P_SERVICE_PEER_PING_(SUCCESS|FAILED)"' "$RUN/android_logcat_live.txt"
kill $LC 2>/dev/null
