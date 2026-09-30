#!/bin/bash
# N3 native call timeline: presentation updates, presented/ringing/accepted events, notification posts (app pid).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
awk '($2 >= "20:04:40" && $2 <= "20:05:40")' "$L" | grep -iE "presentation|LockedCall|updateLockedPresentation|PRESENTED|MknoonCall|CallStyle|call_notification|\"CALL_STATE_TRANSITION\"|CALL_NATIVE|CALL_LOCKED" | grep -v Maestro | cut -c1-230 | head -40
