#!/bin/bash
# Relay v1.10.2 deploy record — APNs VoIP wakes routed per token environment
# with a one-shot cross-environment fallback (dev-signed iPhones carry a
# sandbox PushKit token but report "production"; Apple's BadDeviceToken at the
# production door made the relay revoke the token, the phone then failed
# closed on CALL_STALE_EPOCH and withdrew its endpoint mid-call — 2026-09-04).
# Runs ON THE BOX via the paramiko helper (scratchpad relay_ssh.py, bash -s);
# the binary is uploaded to /tmp/relay-server-v1102 beforehand. Result in
# deploy_relay_v1102_result.txt. Rollback: sudo install -m0755 <backup> \
#   /usr/local/bin/relay-server && sudo systemctl restart relay-server
set -u
EXPECTED_SHA="ded40f82256b2ed31e669ae66d7f19dd22fe1b5c5350af7b41c4726d849c4f45"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.10.2 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
UPLOADED=$(sha256sum /tmp/relay-server-v1102 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q 'sent_cross_environment' /tmp/relay-server-v1102; then echo "ABORT: symbol probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^relay_apns_voip_push_attempts_total\{outcome="(sent|invalid_token)"\}'
echo "--- install ---"
BACKUP="/usr/local/bin/relay-server.pre-1.10.2-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
sudo install -m0755 /tmp/relay-server-v1102 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
sleep 6
echo "--- post-restart ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-30s" --no-pager | grep -aE 'Starting relay-server v|\[APNS_VOIP\]|backend=redis|panic|fatal' | cut -c1-220
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled|^relay_apns_voip_push_attempts_total\{outcome="sent_cross_environment"\}'
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"; done
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
