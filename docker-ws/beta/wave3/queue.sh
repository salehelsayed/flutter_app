#!/bin/bash
# Wave 3 device queue, run from the container; campaigns run in the wave3-next worktree on the Mac.
#   queue.sh run:<k1,k2,...>:<sc1,sc2,...> probe:<k>:<scenario>:<spec> ...
#   QCONFIG=<Mac path of a device config>   QAVDS='7|6a' (or '7|6a|8'; 'none' for iOS) waits while those
#   emulators are throttled. Waits for: no foreign checks run, no source edit in the worktree for 5 min.
W=/workspace/.claude/worktrees/wave3-next
Q=/workspace/docker-ws/beta/wave3
cd "$W" || exit 1
export PROBE_ROOT=$W
busy(){ timeout 90 /claude-host-bin/host-run bash /workspace/docker-ws/wave3_host_ps.sh 2>/dev/null | GRAPH_OK=1 grep -q "scripts/mknoon_checks.py run"; }
edited(){ [ -n "$(GRAPH_OK=1 find lib test tool/sims integration_test scripts android ios assets packages third_party go-mknoon go-relay-server pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml -type f -mmin -$1 -not -path '*/build/*' -not -path '*/.gradle/*' -not -path '*/Pods/*' -not -path '*/.dart_tool/*' -not -path '*/DerivedData/*' -not -path '*/.cxx/*' -not -path '*/ephemeral/*' -not -path '*/__pycache__/*' 2>/dev/null | head -1)" ]; }
throttled(){ timeout 60 /claude-host-bin/host-run bash /workspace/docker-ws/wave3_host_qemu_prio.sh 2>/dev/null | awk -v avds="^Pixel_(${QAVDS:-7|6a})$" '$3 ~ avds && $5 == 4 {t=1} END {exit !t}'; }
quiet(){ while busy || edited 5 || throttled; do echo "not quiet $(date +%H:%M)"; sleep 120; done; echo "quiet $(date +%H:%M)"; }
proof(){ local p; p=$(ls -td build/sims/proofs/production.group_catalog.$1/attempt-* 2>/dev/null | head -1); echo "-- $1: $p"
  head -c 500 $p/first-failure.txt 2>/dev/null; echo; cat $p/oracle.json 2>/dev/null | head -c 600; echo; }
for e in "$@"; do IFS=: read kind k sc spec <<<"$e"
  quiet
  if GRAPH_OK=1 grep -rqs "NEGATIVE PROBE" integration_test lib tool/sims test; then
    echo "ABORT: a NEGATIVE PROBE edit is in the worktree; restore it first"; exit 3; fi
  checks=$(echo "$k" | tr ',' '\n' | sed 's/^/production-group-/' | paste -sd, -)
  tag=$(echo "$k" | tr ',' '+'); log=$Q/logs/$tag-$kind-$(date +%m%d%H%M).log; mkdir -p $Q/logs
  [ "$kind" = probe ] && python3 $Q/probe_apply.py apply $Q/probes/$spec.json
  timeout 90 /claude-host-bin/host-run bash /workspace/docker-ws/wave3_host_load.sh 2>/dev/null | head -1
  /claude-host-bin/host-run bash /workspace/docker-ws/beta/wt_campaign.sh "$checks" "${QCONFIG:-}" > $log 2>&1
  if [ "$kind" = probe ]; then python3 $Q/probe_apply.py restore $Q/probes/$spec.json
    cmp -s $Q/probes/$spec.json.orig $W/$(python3 -c "import json;print(json.load(open('$Q/probes/$spec.json'))['file'])") && echo "restored byte-for-byte"; fi
  echo "== $kind $k  (log $log)"; GRAPH_OK=1 grep -E "^(PASS|FAIL|BLOCKED) production|^Wall|^Report" $log
  for s in $(echo "$sc" | tr ',' ' '); do proof $s; done
done
echo QUEUE-DONE
