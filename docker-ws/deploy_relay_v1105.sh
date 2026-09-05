#!/bin/bash
# Relay v1.10.5 deploy record — the call store receipt reports the wake
# outcome (`wake: dispatched|failed`, opt-in via the client's `wakeReceipt`
# request flag so older clients, which refuse unknown response fields, are
# untouched). The caller rings back as soon as the callee's device was
# alerted: a headless Android callee signals nothing before it is answered
# (device 2026-09-05 16:10Z). Deploy BEFORE the phones: a new client's
# `wakeReceipt` flag is an unknown request field to v1.10.4. Runs ON THE BOX
# via docker-ws/relay_ssh.py (bash -s); the binary is uploaded to
# /tmp/relay-server-v1105 beforehand with docker-ws/relay_sftp_put.py.
# Result in deploy_relay_v1105_result.txt.
# Rollback: sudo install -m0755 <backup> /usr/local/bin/relay-server && \
#   sudo systemctl restart relay-server
set -u
EXPECTED_SHA="10e4bd449208940d061ad05a0ddfda8103200315be8da56ab7c31f7aac2223f1"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.10.5 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
UPLOADED=$(sha256sum /tmp/relay-server-v1105 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q '1\.10\.4' /tmp/relay-server-v1105; then echo "ABORT: version probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
echo "--- install ---"
BACKUP="/usr/local/bin/relay-server.pre-1.10.5-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
sudo install -m0755 /tmp/relay-server-v1105 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
sleep 6
echo "--- post-restart ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-30s" --no-pager | grep -aE 'Starting relay-server v|\[APNS_VOIP\]|backend=redis|panic|fatal' | cut -c1-220
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"; done
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
