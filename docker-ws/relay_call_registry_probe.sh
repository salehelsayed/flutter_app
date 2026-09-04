#!/bin/bash
# Read-only probe of the production relay's call-control registry, run ON the
# relay box:  python3 docker-ws/relay_ssh.py < docker-ws/relay_call_registry_probe.sh
#
# Plan 400 device proofs (TC-400-16/20): prints every relay:call:v1 endpoint /
# token / token-generation record (token and routingHandle masked, never the
# redis password) plus the APNs VoIP push and TURN credential counters.
set -u
RURL=$(sudo grep '^REDIS_URL=' /etc/mknoon/relay-server.env | cut -d= -f2-)
PASS=$(python3 -c 'import sys,urllib.parse as u; p=u.urlparse(sys.argv[1]); print(u.unquote(p.password or ""))' "$RURL")
rc() { redis-cli --no-auth-warning -h localhost -p 6379 -a "$PASS" "$@"; }
mask() {
  python3 -c '
import re, sys
for line in sys.stdin:
    line = line.rstrip("\n")
    line = re.sub(r"(\"token\"\s*:\s*\")([^\"]{6})[^\"]*(\")", r"\1\2…\3", line)
    line = re.sub(r"(\"routingHandle\"\s*:\s*\")([^\"]{4})[^\"]*(\")", r"\1\2…\3", line)
    print(line)'
}

echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') relay call registry ==="
for pattern in 'relay:call:v1:endpoint*' 'relay:call:v1:token:*'; do
  for key in $(rc --scan --pattern "$pattern" | sort); do
    echo "--- $key (ttl $(rc TTL "$key")s)"
    if [ "$(rc TYPE "$key")" = "hash" ]; then
      rc HGET "$key" record | mask
    else
      rc GET "$key" | mask
    fi
  done
done
for key in $(rc --scan --pattern 'relay:call:v1:token-generation:*' | sort); do
  echo "--- $key"
  rc HGETALL "$key"
done
echo "--- metrics"
curl -s localhost:2112/metrics | grep -E '^relay_apns_voip_push_attempts_total|^relay_turn_credential_requests_total' || true
