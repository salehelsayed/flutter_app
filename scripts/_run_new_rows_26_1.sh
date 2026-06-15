#!/usr/bin/env bash
# Temp driver: run ONLY the 6 new group sim rows on the iOS 26.1 simulators.
# continue-on-failure (B02 is RED by design). Per-row PASS/FAIL markers for triage.
set -u
RELAY='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
SIMS4='38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485'
SIM1='38FECA55-03C1-4907-BD9D-8E64BF8E3469'

run_mp() {
  local id="$1"
  echo "===== ROW ${id} START $(date) ====="
  MKNOON_RELAY_ADDRESSES="$RELAY" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario "$id" -d "$SIMS4"
  echo "===== ROW ${id} EXIT=$? END $(date) ====="
}

# greens/divergence first, then the red-by-design B02, then the single-device K04.
run_mp private_voluntary_leave_convergence
run_mp private_media_reaction_roundtrip
run_mp private_override_removal_nonconvergence
run_mp private_online_dissolve_convergence
run_mp private_stale_roster_recipient_omission

echo "===== ROW K04 run_notification_open_ui_smoke START $(date) ====="
MKNOON_RELAY_ADDRESSES="$RELAY" dart run integration_test/scripts/run_notification_open_ui_smoke.dart -d "$SIM1"
echo "===== ROW K04 EXIT=$? END $(date) ====="

echo "ALL_NEW_ROWS_DONE $(date)"
