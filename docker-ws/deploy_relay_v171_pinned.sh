#!/bin/bash
# Deploy relay v1.7.1 attempt 2 — build with the repo-pinned toolchain
# (GOTOOLCHAIN=go1.25.0; go1.26 stdlib panics pinned quic-go: "crypto/tls bug").
# Verifies embedded toolchain before upload and 90s crash-loop-free stability after.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/deploy_relay_v171_pinned_result.txt"

{
  echo "=== attempt-2 started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  cd "$REPO/go-relay-server"
  echo "--- building linux/amd64 with pinned toolchain ---"
  GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 go build -o relay-server-linux-v171 .
  echo "--- embedded toolchain check (must say go1.25.0) ---"
  go version relay-server-linux-v171

  echo "--- uploading ---"
  scp -i "$KEY" -o StrictHostKeyChecking=accept-new relay-server-linux-v171 "$HOST":/tmp/relay-server-v171-pinned

  echo "--- backup + install + restart ---"
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" '
    set -e
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)
    sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.pre-315-attempt2-$STAMP
    sudo install -m0755 /tmp/relay-server-v171-pinned /usr/local/bin/relay-server
    sudo systemctl restart relay-server
    BASE_RESTARTS=$(systemctl show relay-server -p NRestarts --value)
    echo "baseline NRestarts=$BASE_RESTARTS"
    sleep 12
    echo "--- t+12s ---"
    systemctl is-active relay-server
    sudo journalctl -u relay-server --since "-20 seconds" --no-pager | grep -E "Starting relay-server" | tail -2
    sleep 40
    echo "--- t+52s ---"
    systemctl is-active relay-server
    systemctl show relay-server -p NRestarts --value
    sleep 40
    echo "--- t+92s (NRestarts must equal baseline; no panic lines) ---"
    systemctl is-active relay-server
    systemctl show relay-server -p NRestarts --value
    sudo journalctl -u relay-server --since "-100 seconds" --no-pager | grep -cE "panic|Scheduled restart" || true
    echo "--- recent connection evidence ---"
    sudo journalctl -u relay-server --since "-90 seconds" --no-pager | grep -E "Peer connected|quic|Token registered" | tail -6 || true
  '
  echo "=== attempt-2 finished $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
} > "$OUT" 2>&1

echo "wrote $OUT"
