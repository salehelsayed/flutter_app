#!/bin/bash
# Discovery-fix proof: tap Start transfer on the Pixel at a chosen discovery age, then watch the flow log for connect or failure.
#   df_start_timed.sh <label> late|early|now [cancel|complete]
#   late  = wait until the newest LOCAL_MDNS_PEER_FOUND is at least 36 s old (none newer), then Start
#   early = Start at once (caller runs it within ~3 s of the receiver QR showing)
#   cancel = after connect (encrypting stage) tap Cancel transfer
set -uo pipefail
S=21071FDF600CSC; E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/erase-claims-20261023T2103Z
L="$1"; MODE="$2"; END_MODE="${3:-cancel}"; D="$(dirname "$0")"
PID=$(adb -s $S shell pidof com.mknoon.sims.t011 | tr -d '\r')
ev() { adb -s $S logcat -d -v epoch 2>/dev/null | awk -v p="$PID" '$2==p' | grep -a -E "$1"; }
now() { adb -s $S shell date +%s.%N | tr -d '\r' | cut -c1-14; }
QR="${4:-}"
if [ "$MODE" = late ]; then
  # Late = Start at least 38 s after the first PEER_FOUND that follows the receiver QR (epoch arg 4). The app re-resolves found peers every 20 s,
  # so a healthy entry never ages past ~20 s, the first-found age is what a late user tap looks like.
  [ -n "$QR" ] || { echo "late needs the QR-shown epoch"; exit 2; }
  for i in $(seq 1 400); do
    F1=$(ev 'LOCAL_MDNS_PEER_FOUND' | awk -v q="$QR" '$1>=q' | head -1 | awk '{print $1}')
    [ -n "$F1" ] && python3 -c "import sys; sys.exit(0 if $(now)-$F1>=38 else 1)" && break
    sleep 0.5
  done
fi
LP=$(ev 'LOCAL_MDNS_PEER_FOUND' | tail -1 | awk '{print $1}')
T0=$(now)
python3 "$D/erc_ap.py" px tap "desc:Start transfer" >/dev/null || { echo "START TAP FAILED"; exit 2; }
FP=$( [ -n "$QR" ] && ev 'LOCAL_MDNS_PEER_FOUND' | awk -v q="$QR" '$1>=q' | head -1 | awk '{print $1}')
echo "$L qr_shown_epoch=${QR:-na} first_peer_found_after_qr=${FP:-none} start_epoch=$T0 last_peer_found_epoch=${LP:-none} age_at_start=$( [ -n "$LP" ] && python3 -c "print(round($T0-$LP,1))" || echo na)"
RES=""
for i in $(seq 1 90); do
  X=$(ev 'ACCOUNT_MIGRATION_TRANSFER_STAGE|TRANSFER_SUCCEEDED|TRANSFER_FAILED|localPeerUnavailable|RESOLVE_ON_SEND' | awk -v t="$T0" '$1>=t')
  if echo "$X" | grep -q -E 'encrypting|transferringDatabase'; then RES=connected; break; fi
  if echo "$X" | grep -q -E 'TRANSFER_FAILED|localPeerUnavailable'; then RES=failed; break; fi
  sleep 0.5
done
TC=$(now)
echo "$X" | grep -a -o -E '"(event|stage)":"[A-Za-z_]+"|RESOLVE_ON_SEND[^,]{0,80}' | uniq | tr '\n' ' '; echo
echo "$L result=${RES:-timeout} t_from_start=$(python3 -c "print(round($TC-$T0,1))")"
if [ "$RES" = connected ] && [ "$END_MODE" = cancel ]; then
  for k in 1 2 3 4 5; do python3 "$D/erc_ap.py" px tap "desc:Cancel transfer" >/dev/null 2>&1 && { echo "cancel tapped"; break; }; sleep 0.3; done
fi
if [ "$END_MODE" = complete ] && [ "$RES" = connected ]; then
  for i in $(seq 1 120); do ev 'TRANSFER_SUCCEEDED|TRANSFER_FAILED' | awk -v t="$T0" '$1>=t' | grep -q . && break; sleep 1; done
  ev 'TRANSFER_SUCCEEDED|TRANSFER_FAILED' | awk -v t="$T0" '$1>=t' | grep -a -o -E 'TRANSFER_(SUCCEEDED|FAILED)' | head -1
fi
adb -s $S logcat -d -v epoch 2>/dev/null | awk -v t="$(python3 -c "print($T0-120)")" '$1>=t' | grep -a -E 'FLOW|MDNS|MIGRATION' > "$E/run_${L}.logcat"
