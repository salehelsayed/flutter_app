#!/bin/bash
# Erase notification-state proof (c): with the receiver QR already showing, force-stop and relaunch the Pixel test app,
# keep the test process's full logcat from launch, and time the first LOCAL_MDNS_PEER_FOUND.
#   ens_relaunch.sh <label> <qr-shown-epoch> [max-wait-s]
set -uo pipefail
S=21071FDF600CSC; P=com.mknoon.sims.t011; E=/Volumes/CrucialX9/flutter_app/.codex-test-logs/onboarding-discovery-20261024T0005Z
L="$1"; QR="$2"; MAX="${3:-240}"
now() { adb -s $S shell date +%s.%N | tr -d '\r' | cut -c1-14; }
TK=$(now); adb -s $S shell am force-stop $P
sleep 1
TL=$(now); adb -s $S shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
PID=""
for i in $(seq 1 40); do PID=$(adb -s $S shell pidof $P | tr -d '\r'); [ -n "$PID" ] && break; sleep 0.25; done
[ -n "$PID" ] || { echo "no pid"; exit 2; }
FOUND=""; DS=""
END=$(python3 -c "print($TL+$MAX)")
while python3 -c "import sys; sys.exit(0 if $(now) < $END else 1)"; do
  X=$(adb -s $S logcat -d -v epoch 2>/dev/null | awk -v p="$PID" -v t="$TL" '$2==p && $1>=t')
  [ -z "$DS" ] && DS=$(echo "$X" | grep -a -m1 'LOCAL_MDNS_DISCOVERY_START' | awk '{print $1}')
  FOUND=$(echo "$X" | grep -a -m1 '"LOCAL_MDNS_PEER_FOUND"' | awk '{print $1}')
  [ -n "$FOUND" ] && break
  sleep 0.5
done
adb -s $S logcat -d -v epoch 2>/dev/null | awk -v p="$PID" -v t="$(python3 -c "print($TK-2)")" '$1>=t && ($2==p || /NsdManager|NsdService|MdnsDiscovery|mdns/)' > "$E/run_${L}_launch.logcat"
r() { [ -n "$2" ] && python3 -c "print(round($2-$1,1))" || echo none; }
echo "$L qr_shown=$QR kill=$TK launch=$TL pid_up discovery_start=${DS:-none} first_peer_found=${FOUND:-none} launch_to_found=$(r $TL "$FOUND") qr_to_kill=$(r $QR $TK)"
[ -n "$FOUND" ] || exit 1
