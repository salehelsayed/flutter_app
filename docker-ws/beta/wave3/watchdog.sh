#!/bin/bash
# Wave 3 run watchdog (container side). Polls once a minute; EXITS (so the session is notified) on:
#   DONE   the queue log has QUEUE-DONE or ABORT
#   STALL  a checks run is active but no proof/log file changed for STALL_S seconds
#   SIMS   fewer than NEED_SIMS simulators are booted while a run is active
#   WAIT   the queue has not started a run for WAIT_S seconds
# It clears orphaned `flutter build ios` helpers by itself (they hold a finished build's output pipe).
#   watchdog.sh <queue log> [NEED_SIMS=3]
LOG=$1; NEED_SIMS=${2:-3}; STALL_S=${STALL_S:-600}; WAIT_S=${WAIT_S:-1200}
started=$(date +%s); seen_run=0
probe(){ timeout 100 /claude-host-bin/host-run bash /workspace/docker-ws/beta/r79_progress.sh 2>/dev/null; }
while true; do
  if GRAPH_OK=1 grep -q -E "QUEUE-DONE|ABORT" "$LOG" 2>/dev/null; then echo "DONE $(date -u +%T)"; sed -n '/^== /,$p' "$LOG" | cut -c1-300 | head -40; exit 0; fi
  p=$(probe); v(){ echo "$p" | sed -n "s/^$1=//p" | awk '{print $1}'; }
  checks=$(v checks_pid); age=$(v progress_age); orph=$(v orphan_build_helpers); sims=$(v booted_sims)
  if [ "${orph:-0}" -gt 0 ]; then
    echo "$(date -u +%T) auto-clearing $orph orphaned build helpers"
    timeout 100 /claude-host-bin/host-run bash /workspace/docker-ws/beta/r78_kill_build_orphans.sh 2>&1 | tail -1
  fi
  if [ "$checks" != "none" ] && [ -n "$checks" ]; then
    seen_run=1
    # A new checks run resets the clock: no stall before it has run STALL_S seconds.
    [ "$checks" != "${run_pid:-}" ] && { run_pid=$checks; run_start=$(date +%s); echo "$(date -u +%T) run $checks started"; }
    [ "${age:-0}" -gt $(( $(date +%s) - run_start )) ] && age=$(( $(date +%s) - run_start ))
    if [ "${sims:-0}" -lt "$NEED_SIMS" ]; then echo "SIMS only ${sims:-0} booted $(date -u +%T)"; echo "$p"; exit 2; fi
    if [ "${age:-0}" -gt "$STALL_S" ]; then echo "STALL no progress for ${age}s $(date -u +%T)"; echo "$p"; exit 3; fi
  elif [ $seen_run = 0 ] && [ $(( $(date +%s) - started )) -gt "$WAIT_S" ]; then
    echo "WAIT queue has not started a run after ${WAIT_S}s $(date -u +%T)"; tail -3 "$LOG"; exit 4
  fi
  sleep 60
done
