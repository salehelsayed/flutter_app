#!/bin/bash
# Run the change-mode checks in a worktree on the Mac, detached, output to a log file.
#   host-run bash docker-ws/run_mknoon_checks_wt.sh <worktree> <base> <only> <logdir>
set -uo pipefail
WT="$1"; BASE="$2"; ONLY="$3"; LOG="$4"
mkdir -p "$LOG"
export ANDROID_HOME="/Volumes/CrucialX9/mac-development/android-sdk" ANDROID_SDK_ROOT="/Volumes/CrucialX9/mac-development/android-sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home GOTOOLCHAIN=go1.27.1
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$WT" || exit 2
nohup python3 scripts/mknoon_checks.py run --mode change --base "$BASE" --local ${ONLY:+--only "$ONLY"} --report-directory "$LOG/report" > "$LOG/run.log" 2>&1 < /dev/null &
echo $! > "$LOG/pid"; echo "started pid $!"
