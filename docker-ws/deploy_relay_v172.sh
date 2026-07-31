#!/bin/bash
# Deploy relay v1.7.2 (plan 316) — PINNED TOOLCHAIN RULE (go1.25.0), embedded
# check, backup, 90s stability window, TC-08 baselines, plan-315 wake check.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/deploy_relay_v172_result.txt"

{
  echo "=== v1.7.2 deploy started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  cd "$REPO/go-relay-server"
  GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 go build -o relay-server-linux-v172 .
  echo "--- embedded toolchain (must be go1.25.0) ---"
  go version relay-server-linux-v172
  shasum -a 256 relay-server-linux-v172

  scp -i "$KEY" -o StrictHostKeyChecking=accept-new relay-server-linux-v172 "$HOST":/tmp/relay-server-v172

  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
    set -e
    echo "--- TC-08 pre-deploy baselines ---"
    sudo journalctl -u relay-server --since "-24 hours" --no-pager | grep -a -c "Refusing oversized" || true
    sudo journalctl -u relay-server --since "-24 hours" --no-pager | grep -a -c "after provider rejected" || true
    curl -s localhost:2112/metrics | grep -aE "payload_too_large" | grep -v "^#" || echo "no payload_too_large counters yet"
    echo "--- plan-315 wake lines since v1.7.1 (task-4 verification) ---"
    sudo journalctl -u relay-server --since "2026-07-31 22:30" --no-pager | grep -a "GROUP_REACTION_WAKE" | tail -6 || echo "no wake lines yet (no reaction traffic since v1.7.1)"
    curl -s localhost:2112/metrics | grep -a "relay_group_reaction_wake" | grep -v "^#" || echo "wake counter: no increments yet"
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)
    sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.pre-316-$STAMP
    sudo install -m0755 /tmp/relay-server-v172 /usr/local/bin/relay-server
    sudo systemctl restart relay-server
    BASE=$(systemctl show relay-server -p NRestarts --value)
    echo "baseline NRestarts=$BASE"
    sleep 12
    echo "--- t+12s ---"; systemctl is-active relay-server
    sudo journalctl -u relay-server --since "-20 seconds" --no-pager | grep -a "Starting relay-server" | tail -1
    sleep 40
    echo "--- t+52s ---"; systemctl is-active relay-server; systemctl show relay-server -p NRestarts --value
    sleep 40
    echo "--- t+92s ---"; systemctl is-active relay-server; systemctl show relay-server -p NRestarts --value
    sudo journalctl -u relay-server --since "-100 seconds" --no-pager | grep -a -cE "panic|Scheduled restart" || true
    echo "--- post-deploy peer evidence ---"
    sudo journalctl -u relay-server --since "-90 seconds" --no-pager | grep -aE "Peer connected|Token registered" | tail -5 || true
  '
  echo "=== v1.7.2 deploy finished $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} > "$OUT" 2>&1

echo "wrote $OUT"
