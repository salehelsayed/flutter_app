#!/bin/bash
# Background: fresh central builds for the chat-group check, then launch it with device-config-chatgroup.json.
# Usage: <central label> <check label>. Log: <run>/<central label>.driver.log
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree || exit 4
central="$1"; label="$2"; set --
source "$run/run-env-after-source039.sh" >/dev/null 2>&1; set +euo pipefail
(
  python3 /Volumes/CrucialX9/flutter_app/docker-ws/alltests_central_builds.py "$central" &&
  bash /Volumes/CrucialX9/flutter_app/docker-ws/alltests_launch.sh full.group-reaction.ios_chat_group_message_and_reaction_recipient "$label" device-config-chatgroup.json
) > "$run/$central.driver.log" 2>&1 < /dev/null &
echo "driver pid $!"
