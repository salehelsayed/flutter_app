#!/bin/bash
# Readiness gates for the beta call scenarios (sourced by run_fixed3.sh).
# All checks are read-only. Each prints one line for the timeline.

host_ms() { perl -MTime::HiRes=time -e 'printf("%d\n", time()*1000)'; }

# Emulator clock skew, measured with the adb round trip bracketed by host time.
# Prints: skew_ms latency_ms   (skew > 0 = emulator ahead of the Mac)
emu_skew() {
  local t0 t1 e
  t0=$(host_ms)
  e=$($ADB shell 'date +%s%N' 2>/dev/null | tr -d '\r')
  t1=$(host_ms)
  case "$e" in
    *N*|"") e=$(( $($ADB shell date +%s | tr -d '\r') * 1000 + 500 )) ;;
    *) e=$(( e / 1000000 )) ;;
  esac
  echo "$(( e - (t0 + t1) / 2 )) $(( t1 - t0 ))"
}

host_load() { sysctl -n vm.loadavg | awk '{print $2}'; }

# Seconds since the Pixel app's Dart isolate last logged (from the live logcat).
app_quiet_s() {
  local last now
  last=$(tail -c 400000 "$RUN/android_logcat_live.txt" | grep -E " flutter *: " | tail -1 | awk '{print $2}' | cut -c1-8)
  now=$($ADB shell date +%H:%M:%S | tr -d '\r')
  [ -z "$last" ] && { echo 999; return; }
  # modulo one day so a run that crosses midnight still measures correctly
  echo $(( ( $(date -j -f %H:%M:%S "$now" +%s) - $(date -j -f %H:%M:%S "$last" +%s) + 86400 ) % 86400 ))
}

# Waits up to $1 s for the Pixel app to log a successful ping to the iPhone
# (peer 12D3KooWDU) that is newer than the call to this function, with no
# failed ping after it. Returns 0 when seen.
wait_peer_ping() {
  local limit=$1 start i line
  start=$($ADB shell date "'+%m-%d %H:%M:%S'" | tr -d '\r')
  for i in $(seq 1 "$limit"); do
    line=$(tail -c 2000000 "$RUN/android_logcat_live.txt" \
      | grep -E '"event":"P2P_SERVICE_PEER_PING_(SUCCESS|FAILED)","details":\{"peerId":"12D3KooWDU"' \
      | awk -v s="$start" '($1 " " $2) >= s' | tail -1)
    case "$line" in *PING_SUCCESS*) return 0 ;; esac
    sleep 1
  done
  return 1
}

# One gate pass before a scenario. Waits for: emulator adb round trip < 3 s,
# |clock skew| < 2 s, Pixel Dart isolate logged within 20 s, and a fresh
# Pixel->iPhone ping success. Records the result; never blocks longer than ~4 min.
gate() {
  local label=$1 sk lat q load ok=1
  read -r sk lat < <(emu_skew)
  load=$(host_load)
  for i in 1 2 3 4 5 6; do
    q=$(app_quiet_s)
    [ "$lat" -lt 3000 ] && [ "$q" -le 20 ] && break
    sleep 10; read -r sk lat < <(emu_skew)
  done
  wait_peer_ping 150 && ping=ok || { ping=none; ok=0; }
  [ "${sk#-}" -lt 2000 ] || ok=0
  [ "$lat" -lt 3000 ] || ok=0
  [ "$q" -le 20 ] || ok=0
  echo "[$(date '+%H:%M:%S')] gate $label: $([ $ok = 1 ] && echo PASS || echo DEGRADED) skew=${sk}ms adb=${lat}ms dart_quiet=${q}s ping=$ping mac_load=$load" >> "$RUN/timeline.txt"
}
