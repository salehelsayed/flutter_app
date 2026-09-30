#!/bin/bash
# Read-only: all lines from the app process + errors between two times.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk -v a="$1" -v b="$2" '$2>=a && $2<=b' "$RUN/android_logcat_live.txt" \
  | grep -E " $3 |MissingPlugin|PlatformException|Exception|AndroidRuntime|E Mknoon|W Mknoon|Mknoon" \
  | grep -vE "GROUP|peer:ping|BRIDGE_CALL_TIMING|ID_REPO|remoteIce|FlutterJNI|\"layer\":\"DB\"" | cut -c1-230 | head -n ${4:-50}
