#!/bin/bash
# Relay v1.11.0 deploy record (plan 406, user-approved 2026-10-08) — Go 1.27.1
# and go-libp2p v0.50.0 / quic-go v0.62.0 (was go1.25.0 / v0.38.2 / v0.48.2),
# plus a raised per-IP new-connection rate limit (conn_admission.go: IPv4 /32
# 20/s burst 200) with refusals counted in relay_conn_admission_rejected_total.
# Relay protocol code is unchanged from v1.10.9. Proven before deploy: 56/56
# local and 28/28 Hetzner-test-relay old/new interop rows, device proof.
# Runs ON THE BOX via docker-ws/relay_ssh.py (bash -s); the binary is uploaded
# to /tmp/relay-server-v1110 beforehand with docker-ws/relay_sftp_put.py.
# Result in deploy_relay_v1110_result.txt.
# Rollback: sudo install -m0755 <backup> /usr/local/bin/relay-server && \
#   sudo systemctl restart relay-server
set -u
EXPECTED_SHA="79488697d5d1db58b0393555c6f90b175e463efeee2da8339302bca8cc8961c0"
EXPECTED_LIVE="535d30e65da24d1d797e71dce08a7a1fa375d05dbf646e4fa9cf70c29eaec7db"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.11.0 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
if [ "$LIVE" != "$EXPECTED_LIVE" ]; then echo "ABORT: live binary is not v1.10.9"; exit 2; fi
UPLOADED=$(sha256sum /tmp/relay-server-v1110 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q '1\.11\.0' /tmp/relay-server-v1110; then echo "ABORT: version probe failed"; exit 2; fi
if ! grep -a -q 'relay_conn_admission_rejected_total' /tmp/relay-server-v1110; then echo "ABORT: symbol probe failed"; exit 2; fi
if ! grep -a -q 'go1\.27\.1' /tmp/relay-server-v1110; then echo "ABORT: toolchain probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^go_info|^relay_backend_durable|^relay_apns_voip_push_enabled|^relay_connections_total'
echo "--- install ---"
BACKUP="/usr/local/bin/relay-server.pre-1.11.0-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
sudo install -m0755 /tmp/relay-server-v1110 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
sleep 6
echo "--- post-restart ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-30s" --no-pager | grep -aE 'Starting relay-server v|backend=redis|\[PUSH\] outcome|APNS_VOIP\] enabled|TURN_CREDENTIALS|panic|fatal|Failed' | cut -c1-200
curl -s localhost:2112/metrics | grep -aE '^go_info|^relay_backend_durable|^relay_apns_voip_push_enabled|^relay_conn_admission_rejected_total'
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value) connections_total=$(curl -s localhost:2112/metrics | grep -a '^relay_connections_total' | cut -d' ' -f2)"; done
echo "--- errors since restart ---"
sudo journalctl -u relay-server --since "-100s" --no-pager | grep -acE 'panic|fatal|frame too large'
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
