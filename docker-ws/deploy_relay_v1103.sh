#!/bin/bash
# Relay v1.10.3 deploy record — iOS VoIP wakes are skipped for a recipient
# already attached to the call (it acknowledged an earlier event and nothing
# older is pending: redisCallMeta.AckedEvents). Every stored event used to wake
# the callee by VoIP push, and iOS must present a new incoming call per push,
# which rang the callee again right after the caller hung up (2026-09-05).
# Android data wakes unchanged. Runs ON THE BOX via docker-ws/relay_ssh.py
# (bash -s); the binary is uploaded to /tmp/relay-server-v1103 beforehand with
# docker-ws/relay_sftp_put.py. Result in deploy_relay_v1103_result.txt.
# Rollback: sudo install -m0755 <backup> /usr/local/bin/relay-server && \
#   sudo systemctl restart relay-server
set -u
EXPECTED_SHA="79df9b408f19ea27913bd5ea4eb7aa8ce49fb5b376a9ca4bb1aea9c1a79d8fdc"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.10.3 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
UPLOADED=$(sha256sum /tmp/relay-server-v1103 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q 'ackedEvents' /tmp/relay-server-v1103; then echo "ABORT: symbol probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
echo "--- install ---"
BACKUP="/usr/local/bin/relay-server.pre-1.10.3-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
sudo install -m0755 /tmp/relay-server-v1103 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
sleep 6
echo "--- post-restart ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-30s" --no-pager | grep -aE 'Starting relay-server v|\[APNS_VOIP\]|backend=redis|panic|fatal' | cut -c1-220
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"; done
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
