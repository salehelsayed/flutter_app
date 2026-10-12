#!/bin/bash
# SE-41 T4b device proof watches: iPhone 13 syslog and Pixel 6 logcat, filtered on the Mac.
#   se41_proof_watch.sh start      new capture dir (build/se41-proof/<stamp>), one capture per phone
#   se41_proof_watch.sh status     sizes, last lines, running captures
#   se41_proof_watch.sh grep [re]  proof lines (default: SE41_UPDATE_CHECK and update_check)
#   se41_proof_watch.sh stop
set -u
cd "$(dirname "$0")/.."
. docker-ws/_flutter_sdk_env.sh
U13=00008110-00184D622289801E
PIXEL=21071FDF600CSC
CUR=build/se41-proof/current.txt
mkdir -p build/se41-proof
stop_all() {
  pkill -f "idevicesyslog -u $U13" 2>/dev/null
  pkill -f "adb -s $PIXEL logcat -v threadtime" 2>/dev/null
}
case "${1:-status}" in
  start)
    stop_all; sleep 1
    DIR="$PWD/build/se41-proof/$(date +%y%m%d%H%M%S)"; mkdir -p "$DIR"; echo "$DIR" > "$CUR"
    nohup /bin/bash -c "/opt/homebrew/bin/idevicesyslog -u $U13 | grep --line-buffered -E 'Runner|mknoon|SE41' > '$DIR/iphone13_syslog.txt'" >/dev/null 2>&1 &
    adb -s "$PIXEL" logcat -c 2>/dev/null
    nohup /bin/bash -c "adb -s $PIXEL logcat -v threadtime | grep --line-buffered -E 'SE41_UPDATE_CHECK|WM-|FirebaseMessaging|mknoon.app' > '$DIR/pixel_logcat.txt'" >/dev/null 2>&1 &
    sleep 3; echo "CAPTURE_DIR=$DIR"; pgrep -fl "idevicesyslog -u $U13|logcat -v threadtime" ;;
  status)
    DIR=$(cat "$CUR")
    for f in "$DIR"/*.txt; do echo "$(basename "$f") $(stat -f %z "$f") bytes, last: $(tail -1 "$f" | cut -c1-160)"; done
    pgrep -fl "idevicesyslog -u $U13|logcat -v threadtime" ;;
  grep)
    DIR=$(cat "$CUR"); RE="${2:-SE41_UPDATE_CHECK|update_check|UpdateCheckWorker}"
    for f in "$DIR"/*.txt; do echo "=== $(basename "$f")"; grep -E "$RE" "$f" | tail -"${3:-40}" | cut -c1-320; done ;;
  stop)
    stop_all; sleep 1; pgrep -fl "idevicesyslog -u $U13|logcat -v threadtime" || echo "no captures running" ;;
esac
