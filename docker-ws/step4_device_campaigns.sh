#!/bin/bash
# Run (or plan) the l10n-selected device campaigns for the Step 4 candidate in build/wt-step4. Host-side.
#   host-run bash docker-ws/step4_device_campaigns.sh <plan|run> <checks-csv> <evidence-dir-relative-to-main-checkout>
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-step4; MODE="$1"; CHECKS="$2"; EV="$M/$3"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$W" || exit 2
OUT="$EV/campaigns-$MODE-$(date -u +%Y%m%dT%H%M%SZ)"; LOG="$OUT.stdout.txt"
echo "head=$(git rev-parse HEAD) checks=$CHECKS out=$OUT"
if [ "$MODE" = plan ]; then
  python3 scripts/mknoon_checks.py plan --mode change --base a7508ab52c56fcc32a6c870d0222fc8f4f12fcde --local \
    --only "$CHECKS" --device-config "$EV/device-config.json" --output "$OUT" > "$LOG" 2>&1
else
  python3 scripts/mknoon_checks.py run --mode change --base a7508ab52c56fcc32a6c870d0222fc8f4f12fcde --local \
    --only "$CHECKS" --device-config "$EV/device-config.json" --output "$OUT" > "$LOG" 2>&1
fi
rc=$?; echo "exit=$rc"; tail -15 "$LOG"; exit $rc
