#!/bin/bash
# One Codex-requested VC-014 idle attempt (iPhone already backgrounded >= 6 min): relay Redis snapshot before the dial,
# dial from the Pixel (calls28_vc014_attempt.sh), snapshot ~10 s after the dial, then the ring verdict.
#   calls28_idle_attempt.sh <label>
cd "$(dirname "$0")/.." || exit 2
L="$1"; D=.codex-test-logs/calls-20261028/VC-014
timeout 90 python3 docker-ws/hetzner_ssh.py < docker-ws/vc014/redis_snapshot.sh > "$D/${L}_redis_before.txt" 2>&1
rm -f "$D/${L}_dial.txt"
IOSCAP=${IOSCAP:-.codex-test-logs/calls-20261028/ios13_call_syslog5.txt} bash docker-ws/calls28_vc014_attempt.sh "$L" 40 > "$D/${L}_attempt.txt" 2>&1 &
A=$!
until [ -s "$D/${L}_dial.txt" ]; do sleep 0.5; done
sleep 13
timeout 90 python3 docker-ws/hetzner_ssh.py < docker-ws/vc014/redis_snapshot.sh > "$D/${L}_redis_during.txt" 2>&1
echo "during snapshot taken $(date -u +%T)" >> "$D/${L}_attempt.txt"
wait $A; cat "$D/${L}_attempt.txt"
