#!/bin/bash
# Relay v1.10.9 deploy record — group inbox replies are bounded by bytes as
# well as by count. A page of large group replays (membership and key events
# from long remove/re-add histories) encoded over the 128 KB frame limit was
# never written ("[INBOX] Write error: frame too large"); the client saw a
# closed stream, forced a relay reconnect and asked for the same page again,
# about 20 times a minute (device 2026-10-02). group_retrieve_cursor pages now
# stop before 96 KB of messages (always at least one) and resume by cursor;
# group_retrieve (since) returns a budgeted page plus nextCursor, which
# current clients already follow. On top of v1.10.8 (live since 2026-09-28)
# the source also carries the group wake "attempted" counter of c4b38285f.
# Runs ON THE BOX via docker-ws/relay_ssh.py (bash -s); the binary is uploaded
# to /tmp/relay-server-v1109 beforehand with docker-ws/relay_sftp_put.py.
# Result in deploy_relay_v1109_result.txt.
# Rollback: sudo install -m0755 <backup> /usr/local/bin/relay-server && \
#   sudo systemctl restart relay-server
set -u
EXPECTED_SHA="535d30e65da24d1d797e71dce08a7a1fa375d05dbf646e4fa9cf70c29eaec7db"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.10.9 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
LIVE=$(sha256sum /usr/local/bin/relay-server | cut -c1-64); echo "live binary: $LIVE"
UPLOADED=$(sha256sum /tmp/relay-server-v1109 | cut -c1-64); echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
if ! grep -a -q '1\.10\.9' /tmp/relay-server-v1109; then echo "ABORT: version probe failed"; exit 2; fi
if ! grep -a -q 'capGroupInboxReply' /tmp/relay-server-v1109; then echo "ABORT: symbol probe failed"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
echo "--- install ---"
BACKUP="/usr/local/bin/relay-server.pre-1.10.9-$STAMP"
sudo cp -p /usr/local/bin/relay-server "$BACKUP" && echo "backup: $BACKUP"
sudo install -m0755 /tmp/relay-server-v1109 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
sleep 6
echo "--- post-restart ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-30s" --no-pager | grep -aE 'Starting relay-server v|backend=redis|panic|fatal' | cut -c1-220
curl -s localhost:2112/metrics | grep -aE '^relay_backend_durable|^relay_apns_voip_push_enabled'
for wait in 12 40 40; do sleep $wait; echo "t+${wait}s: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"; done
echo "--- frame errors since restart ---"
sudo journalctl -u relay-server --since "-100s" --no-pager | grep -ac 'frame too large'
echo "=== done $(date -u +%Y%m%dT%H%M%SZ) ==="
