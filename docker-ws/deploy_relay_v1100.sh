# Executed 2026-09-04 via paramiko (scratchpad relay_ssh.py); result in deploy_relay_v1100_result.txt.
# Security group sg-00631436a462a9bad (eu-north-1) was opened for udp 49152-50175 with the AWS CLI
# on the Mac (rules sgr-005d9a1e2994fc5a2 ipv4, sgr-0413be132bbb5267a ipv6) after this script ran.
# v1.10.1 (sha 2894daf98fd384d349897bdb829410532d9382147f48f23afd950a7205ff68d9) followed the same
# evening: the relay-side bundle validator hard-coded the old 10-minute TTL and rejected every
# one-hour credential as TURN_CREDENTIALS_UNAVAILABLE; backup relay-server.pre-1.10.1-20260904T200347Z.
# APNs VoIP was enabled afterwards (env only, see deploy_relay_v1100_result.txt): key M7T46H43B2 at
# /etc/mknoon/apns_voip_M7T46H43B2.p8, topic com.mknoon.app.voip, team 397R9Q4WMX, production.
# Placeholders __TURN_SECRET__ / __TURN_SECRET_B64__ are substituted at run time; never commit the secret.
set -u
EXPECTED_SHA="977c3133f9efb6815db12528b9f93e4857b8849f3afa79737b8462ae9263b383"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
echo "=== relay v1.10.0 deploy started $STAMP ==="
echo "--- pre-deploy state ---"
echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
echo "coturn: $(systemctl is-active coturn)"
echo "live binary: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
UPLOADED=$(sha256sum /tmp/relay-server-v1100 | cut -c1-64)
echo "uploaded binary: $UPLOADED"
if [ "$UPLOADED" != "$EXPECTED_SHA" ]; then echo "ABORT: uploaded sha mismatch"; exit 2; fi
curl -s localhost:2112/metrics | grep -aE "^relay_push_tokens_by_platform"
echo "turnserver log dir:"; sudo ls -la /var/log/turnserver/ 2>/dev/null | tail -3 || true

echo "--- coturn: switch to REST credentials (use-auth-secret) ---"
sudo cp /etc/turnserver.conf "/etc/turnserver.conf.pre-call-$STAMP"
sudo tee /etc/turnserver.conf >/dev/null <<'CONF'
# mknoon 1:1 voice-call TURN. relay-server mints time-limited REST credentials
# (go-relay-server/turn_credentials.go) from the same shared secret.
# Installed 2026-09-04 with relay v1.10.0; previous static-user config kept as
# /etc/turnserver.conf.pre-call-<stamp>.
listening-port=3478
external-ip=13.60.15.36
realm=mknoun.xyz
use-auth-secret
static-auth-secret=__TURN_SECRET__
fingerprint
no-multicast-peers
no-cli
min-port=49152
max-port=50175
stale-nonce=600
# Never relay into loopback, link-local (EC2 metadata), the VPC or private ranges.
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=::1
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
log-file=/var/log/turnserver/turnserver.log
CONF
# coturn.service runs as User=turnserver: a root-only (600) config is silently
# ignored and coturn starts with NO auth (open relay). Keep it root:turnserver 640.
sudo chown root:turnserver /etc/turnserver.conf && sudo chmod 640 /etc/turnserver.conf
sudo systemctl restart coturn
sleep 3
if [ "$(systemctl is-active coturn)" != "active" ]; then
  echo "coturn failed to start with the new config; restoring the previous config"
  sudo journalctl -u coturn --since "-20 seconds" --no-pager | tail -8
  sudo cp "/etc/turnserver.conf.pre-call-$STAMP" /etc/turnserver.conf
  sudo systemctl restart coturn
  sleep 2
  echo "coturn after restore: $(systemctl is-active coturn)"
  exit 3
fi
echo "coturn: $(systemctl is-active coturn); listening: $(sudo ss -lunp | grep -cE ':3478\s')/udp $(sudo ss -ltnp | grep -cE ':3478\s')/tcp sockets"
sudo journalctl -u coturn --since "-20 seconds" --no-pager | grep -aiE "error|cannot|fail|denied" | head -4 || true

echo "--- relay env: TURN credential minting ---"
sudo cp /etc/mknoon/relay-server.env "/etc/mknoon/relay-server.env.pre-call-$STAMP"
sudo tee -a /etc/mknoon/relay-server.env >/dev/null <<'ENV'

# 1:1 voice calling (relay v1.10.0, 2026-09-04): time-limited coturn REST
# credentials minted for authenticated peers. Secret shared with
# /etc/turnserver.conf static-auth-secret (base64 of the same bytes).
TURN_CREDENTIALS_ENABLED=true
TURN_CREDENTIAL_URLS=turn:mknoun.xyz:3478?transport=udp,turn:mknoun.xyz:3478?transport=tcp
TURN_CREDENTIAL_PRIMARY_SECRET_B64=__TURN_SECRET_B64__
ENV
echo "env TURN keys: $(sudo grep -c '^TURN_' /etc/mknoon/relay-server.env)"

echo "--- relay binary ---"
sudo cp /usr/local/bin/relay-server "/usr/local/bin/relay-server.pre-1.10.0-$STAMP"
sudo install -m0755 /tmp/relay-server-v1100 /usr/local/bin/relay-server
echo "installed: $(sha256sum /usr/local/bin/relay-server | cut -c1-64)"
sudo systemctl restart relay-server
BASE=$(systemctl show relay-server -p NRestarts --value)
echo "baseline NRestarts=$BASE"
sleep 12
echo "--- t+12s ---"
STATE=$(systemctl is-active relay-server)
echo "relay: $STATE NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sudo journalctl -u relay-server --since "-25 seconds" --no-pager | grep -aE "Starting relay-server|TURN_CREDENTIALS|Control-plane|APNS_VOIP|Fatal|fatal|invalid" | head -8
if [ "$STATE" != "active" ] || [ "$(systemctl show relay-server -p NRestarts --value)" != "$BASE" ]; then
  echo "ROLLBACK: relay not stable after install; restoring v1.9.0 binary and env"
  sudo journalctl -u relay-server --since "-30 seconds" --no-pager | tail -12
  sudo install -m0755 "/usr/local/bin/relay-server.pre-1.10.0-$STAMP" /usr/local/bin/relay-server
  sudo cp "/etc/mknoon/relay-server.env.pre-call-$STAMP" /etc/mknoon/relay-server.env
  sudo systemctl restart relay-server
  sleep 8
  echo "relay after rollback: $(systemctl is-active relay-server)"
  sudo journalctl -u relay-server --since "-10 seconds" --no-pager | grep -a "Starting relay-server" | tail -1
  exit 4
fi
sleep 40
echo "--- t+52s ---"; echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
sleep 40
echo "--- t+92s ---"; echo "relay: $(systemctl is-active relay-server) NRestarts=$(systemctl show relay-server -p NRestarts --value)"
echo "panics/scheduled restarts in window: $(sudo journalctl -u relay-server --since "-100 seconds" --no-pager | grep -a -cE "panic|Scheduled restart")"
curl -s localhost:2112/metrics | grep -aE "^relay_backend_durable|^relay_push_tokens_by_platform|^relay_turn"
echo "post-deploy peer evidence:"; sudo journalctl -u relay-server --since "-90 seconds" --no-pager | grep -aE "Peer connected|Token registered" | tail -3 || true
echo "symbol probe mknoon.call_mailbox.v1: $(grep -a -c mknoon.call_mailbox.v1 /usr/local/bin/relay-server)"
echo "backups: /usr/local/bin/relay-server.pre-1.10.0-$STAMP /etc/mknoon/relay-server.env.pre-call-$STAMP /etc/turnserver.conf.pre-call-$STAMP"
echo "=== relay v1.10.0 deploy finished $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
