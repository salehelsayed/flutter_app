#!/bin/bash
# Run one command in the Codex-UI audio worktree. Output goes to <log> (relative to the worktree).
#   host-run bash docker-ws/cui_audio_step.sh <log> -- <command...>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-audio
LOG="$1"; shift; [ "$1" = "--" ] && shift
cd "$W" || exit 3
mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:/opt/homebrew/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
export GOTOOLCHAIN=go1.27.1
IP=$(grep -E "^PLAN399_FIXTURE_HOST_IP=" /Volumes/CrucialX9/flutter_app/docker-ws/local_devices.env 2>/dev/null | tail -1 | cut -d= -f2)
[ -n "$IP" ] && export PLAN399_FIXTURE_HOST_IP="$IP"
[ -f .codex-test-logs/cui-devices.txt ] && export RELIABILITY_MULTI_DEVICE_IDS="$(tr -d " \n" < .codex-test-logs/cui-devices.txt)"
echo "start $(date -u +%FT%TZ) head=$(git rev-parse --short HEAD) cmd=$*" > "$LOG"
"$@" >> "$LOG" 2>&1
rc=$?
echo "exit=$rc end=$(date -u +%FT%TZ)" >> "$LOG"
exit $rc
