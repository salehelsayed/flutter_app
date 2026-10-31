#!/bin/bash
# Run (or plan) the l10n-selected device campaigns for the Step 4 on main in build/wt-uiu. Host-side.
#   host-run bash docker-ws/step4_main_campaigns.sh <plan|run> <checks-csv> <evidence-dir-relative-to-main-checkout> [tree under build/, default wt-uiu]
set -uo pipefail
# Hold while another session owns a quiet window (pause file in the main checkout).
while [ -f /Volumes/CrucialX9/flutter_app/.codex-test-logs/PAUSE-native ]; do sleep 20; done
M=/Volumes/CrucialX9/flutter_app; W=$M/build/${4:-wt-uiu}; MODE="$1"; CHECKS="$2"; EV="$M/$3"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PLAN399_FIXTURE_GO_TIMEOUT=120m
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"
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
