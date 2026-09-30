#!/bin/bash
# Run the six full.performance.* macOS adapters in sequence on the Mac host.
#
# Commands are the ones pinned in tool/testing/selection.json for
#   full.performance.feed_init / shell_switch / feed_orbit_offscreen /
#   conversation / conversation_sub / orbit
# with the {device:macos} placeholder resolved to the `macos` desktop device.
#
# Sequence, never parallel: these are timing harnesses.
# Runs every target even if an earlier one fails, so one pass reports all six.
set -uo pipefail

REPO=/Volumes/CrucialX9/flutter_app
cd "$REPO"
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
FLUTTER="$SDK/bin/flutter"
if [ ! -x "$FLUTTER" ]; then
  echo "flutter sdk not found at $SDK" >&2
  exit 2
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$REPO/.full_regression_logs/perf-$STAMP"
mkdir -p "$OUT"
echo "LOGDIR=$OUT"
echo "SDK=$($FLUTTER --version 2>&1 | head -1)"
echo "HEAD=$(git rev-parse --short HEAD 2>/dev/null)"

if [ ! -f "$REPO/.dart_tool/package_config.json" ]; then
  echo "=== pub get (package_config.json missing) ==="
  "$FLUTTER" pub get > "$OUT/pub_get.log" 2>&1
  echo "pub_get rc=$?"
fi

ALL_ENTRIES="full.performance.feed_init:FEED_INIT \
full.performance.shell_switch:SHELL_SWITCH \
full.performance.feed_orbit_offscreen:FEED_ORBIT_OFFSCREEN \
full.performance.conversation:CONVERSATION \
full.performance.conversation_sub:CONVERSATION_SUB \
full.performance.orbit:ORBIT"

# Optional args select a subset by PERF_TARGET name, e.g.
#   run_full_performance_groups.sh CONVERSATION CONVERSATION_SUB
if [ "$#" -gt 0 ]; then
  ENTRIES=""
  for want in "$@"; do
    for entry in $ALL_ENTRIES; do
      if [ "${entry##*:}" = "$want" ]; then ENTRIES="$ENTRIES $entry"; fi
    done
  done
  if [ -z "$ENTRIES" ]; then
    echo "no target matched: $*" >&2
    exit 2
  fi
else
  ENTRIES="$ALL_ENTRIES"
fi

overall=0
for entry in $ENTRIES; do
  id="${entry%%:*}"
  target="${entry##*:}"
  log="$OUT/$target.log"
  echo "=== START $id target=$target $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  start="$(date +%s)"
  "$FLUTTER" test --no-pub --machine -d macos \
    "--dart-define=PERF_TARGET=$target" \
    integration_test/performance_harness.dart > "$log" 2>&1
  rc=$?
  end="$(date +%s)"
  if [ "$rc" -ne 0 ]; then overall=1; fi
  echo "=== END $id rc=$rc secs=$((end - start)) log=$log ==="
done

echo "=== ALL DONE overall_rc=$overall logdir=$OUT $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
exit "$overall"
