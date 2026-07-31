#!/bin/bash
# Read-only: inspect registered push-token entries (platform, capabilities,
# updatedAt) for the peers seen in today's test-window groups, to determine
# why the 19:30Z group stores produced zero reaction push fan-out.
# FCM token values are masked; the redis password is never printed.
# Result: docker-ws/relay_push_token_capabilities_309_result.txt
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_push_token_capabilities_309_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

$SSH 'bash -s' > "$OUT" 2>&1 <<'REMOTE'
echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
RAW=$(sudo grep -E '^REDIS_URL=' /etc/mknoon/relay-server.env | head -1 | cut -d= -f2-)
URL=$(printf '%s' "$RAW" | tr -d '"\r' | xargs)
echo "url length=${#URL} scheme=${URL%%://*}"

SCHEME=${URL%%://*}
REST=${URL#*://}
CREDS=""
HOSTPORT=$REST
if [[ "$REST" == *@* ]]; then
  CREDS=${REST%@*}
  HOSTPORT=${REST##*@}
fi
HOSTPORT=${HOSTPORT%%/*}
RHOST=${HOSTPORT%%:*}
RPORT=${HOSTPORT##*:}
[ "$RPORT" = "$RHOST" ] && RPORT=6379
RUSER=""
RPASS=""
if [ -n "$CREDS" ]; then
  if [[ "$CREDS" == *:* ]]; then
    RUSER=${CREDS%%:*}
    RPASS=${CREDS#*:}
  else
    RPASS=$CREDS
  fi
fi
# percent-decode the password if it contains %xx escapes
if [[ "$RPASS" == *%* ]]; then
  RPASS=$(printf '%b' "${RPASS//%/\\x}")
fi
TLS_FLAG=""
[ "$SCHEME" = "rediss" ] && TLS_FLAG="--tls"
echo "host=$RHOST port=$RPORT user_present=$([ -n "$RUSER" ] && echo yes || echo no) pass_len=${#RPASS} tls=${TLS_FLAG:-no}"

rcli() {
  if [ -n "$RUSER" ]; then
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning $TLS_FLAG -h "$RHOST" -p "$RPORT" --user "$RUSER" "$@"
  else
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning $TLS_FLAG -h "$RHOST" -p "$RPORT" "$@"
  fi
}

echo "ping: $(rcli PING)"
if [ "$(rcli PING)" != "PONG" ]; then
  echo "ABORT: cannot authenticate to redis"
  exit 0
fi

echo "push token key count: $(rcli --scan --pattern 'relay:push:*' | wc -l)"

matched=0
for k in $(rcli --scan --pattern 'relay:push:*'); do
  comp=${k#relay:push:}
  pad=$comp
  case $(( ${#comp} % 4 )) in
    2) pad="${comp}==" ;;
    3) pad="${comp}=" ;;
  esac
  p=$(printf '%s' "$pad" | tr '_-' '/+' | base64 -d 2>/dev/null)
  case "$p" in
    12D3KooWLB4TNaHM1D3B*|12D3KooWM43NCsZpuh7Q*|12D3KooWRofUkyAuKdsp*|12D3KooWSmFBWf4T4tjC*|12D3KooWDJ96ouLuM78r*|12D3KooWEnpArQAHp36y*|12D3KooWHyiSmJVcHfQo*|12D3KooWNbc17WZYUM7w*)
      matched=$((matched+1))
      echo
      echo "== peer ${p:0:20}... =="
      rcli GET "$k" | sed -E 's/"Token":"[^"]{6}[^"]*"/"Token":"<masked>"/'
      ;;
  esac
done
echo
echo "matched entries: $matched"
REMOTE

echo "wrote $OUT"
