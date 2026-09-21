#!/bin/bash
# Liveness/progress probe for a running docker-ws/run_sims_major.sh gate.
#
#   bash docker-ws/sims_major_status.sh           # human report
#   bash docker-ws/sims_major_status.sh --brief   # one machine-readable line
#
# Read-only: starts nothing, kills nothing, writes nothing. The oracle for
# "hung vs working" is accumulated CPU time of tool/sims/sims.dart -- a run
# blocked on a dead device stops accumulating it while staying alive, which is
# how a stalled gate previously went 7 hours without anyone noticing.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

brief=0
for a in "$@"; do
  [ "$a" = "--brief" ] && brief=1
done

sims_pids="$(pgrep -f 'tool/sims/sims.dart' 2>/dev/null | tr '\n' ' ')"
npids="$(echo $sims_pids | wc -w | tr -d ' ')"

cpu="none"
if [ "$npids" -gt 0 ]; then
  cpu=""
  for p in $sims_pids; do
    t="$(ps -o time= -p "$p" 2>/dev/null | tr -d ' ')"
    cpu="${cpu}${p}/${t},"
  done
  cpu="${cpu%,}"
fi

# What the gate is actually doing right now, most specific first.
phase="idle"
if pgrep -f 'xcodebuild' >/dev/null 2>&1; then phase="ios-build"
elif pgrep -f 'GradleDaemon|kotlin-daemon|gradlew' >/dev/null 2>&1; then phase="android-build"
elif pgrep -f 'frontend_server|flutter_tools.snapshot' >/dev/null 2>&1; then phase="flutter-build"
elif pgrep -f 'idevicesyslog|devicectl|xcrun simctl' >/dev/null 2>&1; then phase="ios-device"
elif pgrep -f 'adb -s' >/dev/null 2>&1; then phase="android-device"
elif [ "$npids" -gt 0 ]; then phase="planner"
fi

freshlogs="$(find build/sims/logs -name '*.log' -mmin -15 2>/dev/null | wc -l | tr -d ' ')"
freshbuild="no"
if [ -n "$(find build/sims -type f -mmin -15 2>/dev/null | head -1)" ]; then freshbuild="yes"; fi

if [ "$brief" -eq 1 ]; then
  echo "t=$(date -u +%H:%M:%SZ) npids=$npids cpu=$cpu phase=$phase freshlogs=$freshlogs freshbuild=$freshbuild"
  exit 0
fi

echo "sims major status  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  sims.dart pids : ${sims_pids:-<none>}"
echo "  cpu accrued    : $cpu"
echo "  active phase   : $phase"
echo "  logs <15m old  : $freshlogs"
echo "  build/sims warm: $freshbuild"
echo "--- sims process table"
if [ "$npids" -gt 0 ]; then
  ps -o pid,etime,time,%cpu,stat -p $(echo $sims_pids | tr ' ' ',') 2>/dev/null
else
  echo "  (no sims.dart process)"
fi
echo "--- newest row logs"
ls -lat build/sims/logs/*.log 2>/dev/null | head -8
