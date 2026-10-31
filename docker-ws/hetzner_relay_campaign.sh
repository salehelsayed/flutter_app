#!/bin/bash
# Run one sims device check against the Hetzner TEST relay (owner 10-26: testing never uses AWS). No relay SSH keys.
#   host-run bash docker-ws/hetzner_relay_campaign.sh <check-id> <evidence-dir-relative> [tree under build/]
set -uo pipefail
PID=12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM
export MKNOON_RELAY_ADDRESSES="/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/$PID,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/$PID"
# Disposable emulator-pair journeys (DC-002 and similar) require this opt-in from the launcher.
export SIMS_DISPOSABLE_ANDROID_JOURNEYS=1
echo "relay = Hetzner test relay, disposable emulator-pair route on"
# Optional 4th arg "disposable": emulator-pair route for runners that require SIMS_DISPOSABLE_ANDROID_JOURNEYS=1 (host-run does not pass env).
if [ "${4:-}" = disposable ]; then
  export SIMS_DISPOSABLE_ANDROID_JOURNEYS=1; echo "disposable emulator-pair route"
  # AVDs with hw.keyboard=yes hide the soft keyboard, so Maestro hideKeyboard sends BACK and leaves the chat.
  for s in $(grep -o '"emulator-[0-9]*"' "/Volumes/CrucialX9/flutter_app/${2:?evidence}/device-config.json" | tr -d '"' | sort -u); do
    "$HOME/Library/Android/sdk/platform-tools/adb" -s "$s" shell settings put secure show_ime_with_hard_keyboard 1 && echo "$s: soft keyboard on"
  done
fi
exec bash "$(dirname "$0")/step4_main_campaigns.sh" run "${1:?check}" "${2:?evidence}" "${3:-wt-testdocs2}"
