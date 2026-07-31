#!/bin/bash
# Deploy relay v1.7.1 (plan 315 observability leg) to the PRODUCTION EC2 relay.
# Backs up the current binary, installs, restarts, verifies provenance.
# Result: docker-ws/deploy_relay_v171_result.txt
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/deploy_relay_v171_result.txt"

{
  echo "=== deploy started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  command -v go >/dev/null || { echo "FATAL: no go toolchain on host"; exit 2; }
  go version

  cd "$REPO/go-relay-server"
  echo "--- building linux/amd64 ---"
  GOOS=linux GOARCH=amd64 go build -o relay-server-linux-v171 .
  ls -la relay-server-linux-v171

  echo "--- uploading ---"
  scp -i "$KEY" -o StrictHostKeyChecking=accept-new relay-server-linux-v171 "$HOST":/tmp/relay-server-v171

  echo "--- backup + install + restart ---"
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
    set -e
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)
    sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.pre-plan315-$STAMP
    echo "backup: /usr/local/bin/relay-server.pre-plan315-$STAMP"
    sudo install -m0755 /tmp/relay-server-v171 /usr/local/bin/relay-server
    sudo systemctl restart relay-server
    sleep 4
    echo "--- journal (post-restart) ---"
    sudo journalctl -u relay-server -n 30 --no-pager | grep -E "Starting relay-server|backend=|reaction push enabled" || true
    echo "--- durability gauge ---"
    curl -s localhost:2112/metrics | grep -E "relay_backend_durable" || true
    echo "--- wake counter family (empty until first increment is expected) ---"
    curl -s localhost:2112/metrics | grep -c "relay_group_reaction_wake" || true
    echo "--- service state ---"
    systemctl is-active relay-server
  '
  echo "=== deploy finished $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} > "$OUT" 2>&1

echo "wrote $OUT"
