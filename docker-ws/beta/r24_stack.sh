#!/bin/bash
# Live stacks of the app during a transcode stall: Java stacks of all threads via JDWP (jdb; debug build),
# then native backtraces via debuggerd. Output: <run>/extra/stall/{jstack,nstack}_<HHMMSS>.txt
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); OUT="$RUN/extra/stall"; mkdir -p "$OUT"; T=$(date +%H%M%S)
P=$($ADB shell pidof $PKG | tr -d '\r'); echo "app pid $P"
$ADB forward tcp:8711 jdwp:$P
( sleep 4; printf 'suspend\n'; sleep 2; printf 'where all\n'; sleep 12; printf 'resume\n'; sleep 1; printf 'quit\n' ) \
  | timeout 120 "$JAVA_HOME/bin/jdb" -attach localhost:8711 > "$OUT/jstack_$T.txt" 2>&1
$ADB forward --remove tcp:8711
echo "jstack: $(wc -l < "$OUT/jstack_$T.txt") lines"
grep -n -A30 "TranscoderThrea" "$OUT/jstack_$T.txt" | head -45
timeout 120 $ADB shell debuggerd -b $P > "$OUT/nstack_$T.txt" 2>&1
echo "nstack: $(wc -l < "$OUT/nstack_$T.txt") lines"; head -3 "$OUT/nstack_$T.txt"
grep -n -A25 'name: TranscoderThrea' "$OUT/nstack_$T.txt" | head -40
