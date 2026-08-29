#!/bin/bash
# Fresh-identity deploy to iPhone 11 + iPhone 13 + Pixel, with the recurring
# iOS code-seal break repaired automatically, and per-run device telemetry kept.
#
# run_fresh_three_phones.sh uninstalls before installing, so when the
# Flutter.framework seal breaks (ApplicationVerificationFailed 0xe8008001 —
# happens on essentially every iOS build here) it leaves both iPhones with NO
# app. This wrapper runs it, and if it fails, runs resign_and_install_iphones.sh
# to re-sign and install the SAME artifact. Identity is still fresh: the
# uninstall already happened in phase 1.
#
# Everything from one run lands in docker-ws/deploy-captures/<RUN_ID>/ — the two
# result files are otherwise TRUNCATED by the next run, so without this the only
# surviving record is the last deploy.
#
# Device telemetry is streamed for the whole run (started before phase 1, so the
# uninstall/install/launch sequence is inside the capture) and stopped at the end.
# CAVEAT — iPhone Dart logs: phase 1 builds iOS RELEASE, where
# flowEventLoggingEnabled = kDebugMode, so NO Dart [FLOW] lines reach the syslog.
# The iPhone captures hold Swift NSLog ([PUSH_DIAG], [GoBridge]) and Go stderr
# ([NODE], [RELAY_SESSION]) only. To get Dart events too, the iOS build needs
# --dart-define=FDC_FLOW_LOG=1. Android is a debug build, so the Pixel logcat
# has the full [FLOW] stream already.
set -uo pipefail
cd "$(dirname "$0")/.."

# Mirrors the pinned targets in run_fresh_three_phones.sh.
PIXEL_SERIAL=21071FDF600CSC
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"

RUN_ID=$(date +%y%m%d%H%M%S)
CAP_REL="deploy-captures/$RUN_ID"        # relative to docker-ws/
CAP_DIR="docker-ws/$CAP_REL"
mkdir -p "$CAP_DIR"

# Keep a copy of everything this wrapper prints alongside the telemetry.
exec > >(tee -a "$CAP_DIR/deploy.log") 2>&1

CAP_PIDS=""
stop_captures() {
  [ -z "$CAP_PIDS" ] && return 0
  echo "== stopping telemetry captures"
  for p in $CAP_PIDS; do kill "$p" 2>/dev/null; done
  sleep 2
  for p in $CAP_PIDS; do kill -9 "$p" 2>/dev/null; done
  CAP_PIDS=""
}
# Captures must never outlive the wrapper: a stray idevicesyslog holds the
# device relay, and the NEXT run then connects and receives nothing.
trap stop_captures EXIT INT TERM

echo "########## RUN $RUN_ID — captures -> $CAP_DIR ##########"
docker-ws/capture_pixel_logcat.sh "$PIXEL_SERIAL" "$CAP_REL/pixel_logcat.txt" &
CAP_PIDS="$CAP_PIDS $!"
echo "   pixel logcat  -> $CAP_DIR/pixel_logcat.txt (pid $!)"
for UDID in $IPHONE_UDIDS; do
  docker-ws/capture_iphone_syslog_any.sh "$UDID" "$CAP_REL/iphone_${UDID:0:8}_syslog.txt" &
  CAP_PIDS="$CAP_PIDS $!"
  echo "   syslog $UDID -> $CAP_DIR/iphone_${UDID:0:8}_syslog.txt (pid $!)"
done
# capture_iphone_syslog_any.sh sleeps 1s clearing strays before it attaches.
sleep 3

echo "########## PHASE 1: fresh build + uninstall + install ##########"
docker-ws/run_fresh_three_phones.sh
PHASE1=$?
echo "########## PHASE 1 exit=$PHASE1 ##########"
cp -f docker-ws/run_fresh_three_phones_result.txt "$CAP_DIR/phase1_result.txt" 2>/dev/null

PHASE2=0
RESIGNED=no
if [ "$PHASE1" -eq 0 ]; then
  echo "All three phones OK on the first pass — no re-sign needed."
elif ! grep -q 'FAILED(install)' docker-ws/run_fresh_three_phones_result.txt 2>/dev/null; then
  echo "Phase 1 failed for a reason other than an iPhone install — NOT re-signing."
  echo "Look at docker-ws/run_fresh_three_phones_result.txt."
  PHASE2=$PHASE1
else
  echo "########## PHASE 2: re-sign Flutter.framework + app, reinstall iPhones ##########"
  docker-ws/resign_and_install_iphones.sh
  PHASE2=$?
  RESIGNED=yes
  echo "########## PHASE 2 exit=$PHASE2 ##########"
  cp -f docker-ws/resign_and_install_iphones_result.txt "$CAP_DIR/phase2_result.txt" 2>/dev/null
fi

# Let the phones log a few seconds of post-launch startup before cutting the
# streams — the launch itself is the most interesting part of the capture.
echo "== holding captures 15s for post-launch startup"
sleep 15
stop_captures

{
  echo "run_id=$RUN_ID"
  echo "wrapper=docker-ws/fresh_three_phones_with_resign.sh"
  echo "phase1_exit=$PHASE1 phase2_exit=$PHASE2 resigned=$RESIGNED"
  echo "finished=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "ios_dart_flow_logs=no (iOS release build; needs --dart-define=FDC_FLOW_LOG=1)"
  echo "--- phase 1 result ---"
  cat docker-ws/run_fresh_three_phones_result.txt 2>/dev/null
  if [ "$RESIGNED" = yes ]; then
    echo "--- phase 2 result (after re-sign; this is the live state) ---"
    cat docker-ws/resign_and_install_iphones_result.txt 2>/dev/null
  fi
  echo "--- captures ---"
  for f in "$CAP_DIR"/*.txt; do
    [ -e "$f" ] || continue
    echo "$(basename "$f")  $(wc -l < "$f" | tr -d ' ') lines  $(wc -c < "$f" | tr -d ' ') bytes"
  done
} > "$CAP_DIR/MANIFEST.txt"

echo "########## FINAL ##########"
cat "$CAP_DIR/MANIFEST.txt"
echo "########## captures kept in $CAP_DIR ##########"
sleep 1   # let the tee subshell flush before exit
exit "$PHASE2"
