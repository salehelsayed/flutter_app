#!/bin/bash
# Relay v1.11.1 deploy record (user-approved 2026-10-10). Diagnostics only:
# - CALL_DIAGNOSTICS_MAX_BYTES raises the call-diagnostics store ceiling from
#   the fixed 64 MiB to 256 MiB. The full store refused every ordinary event
#   (relay_diagnostics_refusals_total{reason="global_bytes"}), so traces kept
#   only terminal and first-media records.
# - Closed schema gains the preflight reasons transport_startup_timeout,
#   readiness_timeout, contact_check_timeout, preflight_timeout, the booleans
#   transportStarted / withdrawalFailed and the enums startStage / startOutcome.
#   This must be live before an app build that sends them.
# - Also ships the committed 0b61b27c1 (fixed reason classes on call_control
#   log lines). Wire responses, error codes and metric labels are unchanged.
# Built from HEAD 0b61b27c1 + these changes only (clean archive), go1.27.1.
# Runs ON THE BOX via docker-ws/relay_ssh.py (bash -s); the binary is uploaded
# to /tmp/relay-server-v1111 and the summary tool to /tmp/call_diagnostics.py
# beforehand with docker-ws/relay_sftp_put.py.
# Rollback: sudo install -m0755 <backup> /usr/local/bin/relay-server && \
#   sudo rm /etc/systemd/system/relay-server.service.d/zz-call-diagnostics-limit.conf && \
#   sudo systemctl daemon-reload && sudo systemctl restart relay-server
# NOT RUN AS WRITTEN. Live since 2026-10-10T17:46:29Z is sha
# 2bf883dcc1214a32caaf80d401d7e372a63afb23b0a89ebd69373bf52a0bd3c8, built from
# the working tree = HEAD 33b749001 (call routing lease + recovery fixes) plus
# these diagnostics changes. Backup: /usr/local/bin/relay-server.pre-20261010T1740Z
# (= v1.11.0 79488697...). The drop-in and summary tool below were applied.
set -u
EXPECTED_SHA="3249c66ffce5194dc48e2eb692262335f8a8d0e24dd4f5e8b91b0a1721f227f4"
EXPECTED_LIVE="79488697d5d1db58b0393555c6f90b175e463efeee2da8339302bca8cc8961c0"
DROPIN=/etc/systemd/system/relay-server.service.d/zz-call-diagnostics-limit.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.11.1 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
if [ "$LIVE" != "$EXPECTED_LIVE" ]; then echo "ABORT: live binary is not v1.11.0"; exit 2; fi
UPLOADED=$(sha256sum /tmp/relay-server-v1111 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q '1\.11\.1' /tmp/relay-server-v1111; then echo "ABORT: version probe failed"; exit 2; fi
if ! grep -a -q 'CALL_DIAGNOSTICS_MAX_BYTES' /tmp/relay-server-v1111; then echo "ABORT: quota probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^relay_diagnostics_global_limit_bytes|^relay_backend_durable'
echo "--- deploy ---"
BACKUP="/usr/local/bin/relay-server.pre-1.11.1-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
printf '[Service]\nEnvironment="CALL_DIAGNOSTICS_MAX_BYTES=268435456"\n' | sudo tee "$DROPIN" >/dev/null
echo "drop-in: $(cat "$DROPIN" | tr '\n' ' ')"
sudo systemctl daemon-reload
if [ -f /tmp/call_diagnostics.py ]; then
  sudo cp -p /usr/local/bin/call_diagnostics.py "/usr/local/bin/call_diagnostics.py.pre-1.11.1-$STAMP"
  sudo install -m0755 /tmp/call_diagnostics.py /usr/local/bin/call_diagnostics.py
  echo "summary tool: $(sha256sum /usr/local/bin/call_diagnostics.py | cut -c1-64)"
fi
sudo install -m0755 /tmp/relay-server-v1111 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
echo "--- verify ---"
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value) connections_total=$(curl -s localhost:2112/metrics | grep -a '^relay_connections_total' | cut -d' ' -f2)"; done
sudo journalctl -u relay-server --since "-100s" --no-pager | grep -aE 'Starting relay-server v|backend=redis|call_diagnostics|app_diagnostics state|panic|fatal' | cut -c1-200
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_diagnostics_global_limit_bytes|^relay_call_diagnostics_storage_ready|^relay_apns_voip_push_enabled|^relay_turn_credential_issuer_enabled'
echo "panic/fatal lines: $(sudo journalctl -u relay-server --since "-100s" --no-pager | grep -acE 'panic|fatal')"
sudo python3 /usr/local/bin/call_diagnostics.py --dir /var/lib/mknoon/call-diagnostics --hours 1 >/dev/null 2>&1 && echo "summary tool: runs" || echo "summary tool: FAILED"
echo "=== deploy finished $(date -u +%Y%m%dT%H%M%SZ) ==="
