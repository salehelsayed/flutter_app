#!/bin/bash
# Run the original A and R benchmarks (fixed to carry the recipient ML-KEM key) on one iOS simulator with the
# Go CLI test peer, in the wave3-next worktree. Detached; log docker-ws/beta/wave4/benchmarks_ar.out.
#   run_benchmarks_ar.sh <simulator-udid>
if [ -z "${BAR_DETACHED:-}" ]; then
  BAR_DETACHED=1 nohup bash "$0" "$@" >/dev/null 2>&1 &
  echo "started detached (pid $!)"; exit 0
fi
SIM=$1
W=/Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next
OUT=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave4/benchmarks_ar.out
export PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:/opt/homebrew/bin:$PATH"
cd "$W" || exit 1
# The relay over TCP (WSS) as well as QUIC: the Mac's network can block outbound UDP to the relay
# (the test peer's QUIC-only dial timed out 2026-10-05). Same list as docker-ws/run_sims_major.sh.
export MKNOON_RELAY_ADDRESSES="/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g"
{
  echo "start $(date -u +%T) $(git log -1 --format=%h)"
  xcrun simctl boot "$SIM" 2>&1 | tail -1
  xcrun simctl bootstatus "$SIM" -b 2>&1 | tail -1
  (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go build -o bin/testpeer ./cmd/testpeer/) && echo "testpeer built"
  dart run integration_test/scripts/run_benchmark_suite.dart -d "$SIM" --scenarios A,R 2>&1
  echo "suite rc=$?"
  xcrun simctl shutdown "$SIM" 2>&1 | tail -1
  echo "end $(date -u +%T)"
} > "$OUT" 2>&1
