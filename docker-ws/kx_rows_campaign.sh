#!/bin/bash
# Run device-audio limited to chosen KX rows (base proof plus KX_KEEP) through mknoon_checks. Host-side.
#   host-run bash docker-ws/kx_rows_campaign.sh <tree under build/> <kx-csv> <evidence-dir-relative-to-main-checkout> <device-config.json relative>
set -uo pipefail
# Hold while another session owns a quiet window (pause file in the main checkout).
while [ -f /Volumes/CrucialX9/flutter_app/.codex-test-logs/PAUSE-native ]; do sleep 20; done
M=/Volumes/CrucialX9/flutter_app; W=$M/build/${1:?tree}; KEEP="${2:?kx}"; EV="$M/${3:?evidence}"; CFG="$M/${4:?device-config}"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PLAN399_FIXTURE_GO_TIMEOUT=120m
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/.maestro/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export KX_KEEP="$KEEP"
cd "$W" || exit 2
mkdir -p "$EV"
OUT="$EV/kx-$(echo "$KEEP" | tr ',' '-')-$(date -u +%Y%m%dT%H%M%SZ)"; LOG="$OUT.stdout.txt"
echo "head=$(git rev-parse HEAD) keep=$KEEP out=$OUT"
python3 "$M/docker-ws/kx_only_checks.py" run --mode change --base a7508ab52c56fcc32a6c870d0222fc8f4f12fcde --local \
  --only device-audio --device-config "$CFG" --output "$OUT" > "$LOG" 2>&1
rc=$?; echo "exit=$rc" >> "$LOG"; echo "exit=$rc out=$OUT"; tail -12 "$LOG"; exit $rc
