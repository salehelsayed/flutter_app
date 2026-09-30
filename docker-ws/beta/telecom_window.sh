#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk '$2>="22:27:29.2" && $2<="22:27:35.4"' "$RUN/android_logcat_live.txt" \
 | grep -E "Telecom|Mknoon|CallsManager|ConnectionService|TransactionalService|VoipCall|CallControl|addCall|CallException|FGS|ForegroundService|MknoonCall" \
 | grep -vE "CallAudioRouteController.*Message received|StatusBar" | cut -c1-230 | head -40
