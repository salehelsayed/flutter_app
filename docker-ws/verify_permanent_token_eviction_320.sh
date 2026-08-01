#!/bin/bash
# TC-320-13 — deterministic post-deploy behavioural proof for plan 320 P1.
#
# A passive journal grep would read green whether or not the classifier works
# (the triggering event is rare), so this script MAKES the event happen:
#   1. Generates a SCRATCH peer id (testpeer; never a real user).
#   2. On the relay box, copies a KNOWN-DEAD FCM token (found via the pre-deploy
#      retry-ladder journal signature, read from redis) onto the scratch peer.
#      A fabricated token cannot be used: FCM answers INVALID_ARGUMENT for
#      malformed tokens, and that code is deliberately NOT in the permanent set
#      (it would swallow plan 316's oversized-payload rescue). Only a genuinely
#      issued-then-retired token deterministically yields UNREGISTERED.
#   3. Stores ONE ordinary chat envelope to the scratch peer via the production
#      relay (testpeer inbox_store_v1; the ordinary wake gate is fail-open for
#      a recipient that never registered a wake-token set).
#   4. Asserts BOTH: `[PUSH] Removed invalid token for <scratch> … reason=<arm>`
#      appears AND no `retrying in` line exists for that peer, AND the token
#      key is gone from redis (eviction actually deleted it).
#   5. Cleans up every scratch redis key (inbox custody + any token remnant).
#
# Fallback: if no dead token is present in redis but the journal since service
# start already shows a NATURAL eviction with zero retry lines for that peer,
# the semantic outcome is proven by production traffic itself → PASS.
#
# Result: docker-ws/verify_permanent_token_eviction_320_result.txt
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO/se.pem"
HOST=ubuntu@13.60.15.36
OUT="$REPO/docker-ws/verify_permanent_token_eviction_320_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
TP="$REPO/go-mknoon/bin/testpeer"

: > "$OUT"
log() { echo "$@" | tee -a "$OUT"; }

log "=== TC-320-13 verify started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

log "--- building testpeer ---"
(cd "$REPO/go-mknoon" && go build -o bin/testpeer ./cmd/testpeer) >> "$OUT" 2>&1 || {
  log "TC-320-13=FAIL (testpeer build failed)"; exit 1; }

SCRATCH_JSON=$(echo '{"cmd":"generate_identity"}' | "$TP" 2>>"$OUT")
B_PEER=$(printf '%s\n' "$SCRATCH_JSON" | grep -o '"peerId":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$B_PEER" ]; then
  log "TC-320-13=FAIL (could not generate scratch identity)"; exit 1
fi
log "scratch recipient peer: $B_PEER"

log "--- prep leg (relay box): locate dead token, register it for the scratch peer ---"
PREP_OUT=$($SSH "$HOST" 'bash -s' "$B_PEER" <<'REMOTE'
set -u
B="$1"
RAW=$(sudo grep -E '^REDIS_URL=' /etc/mknoon/relay-server.env | head -1 | cut -d= -f2-)
URL=$(printf '%s' "$RAW" | tr -d '"\r' | xargs)
REST=${URL#*://}
CREDS=""; HOSTPORT=$REST
if [[ "$REST" == *@* ]]; then CREDS=${REST%@*}; HOSTPORT=${REST##*@}; fi
HOSTPORT=${HOSTPORT%%/*}; RHOST=${HOSTPORT%%:*}; RPORT=${HOSTPORT##*:}
[ "$RPORT" = "$RHOST" ] && RPORT=6379
RUSER=""; RPASS=""
if [ -n "$CREDS" ]; then
  if [[ "$CREDS" == *:* ]]; then RUSER=${CREDS%%:*}; RPASS=${CREDS#*:}; else RPASS=$CREDS; fi
fi
if [[ "$RPASS" == *%* ]]; then RPASS=$(printf '%b' "${RPASS//%/\\x}"); fi
rcli() {
  if [ -n "$RUSER" ]; then
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning -h "$RHOST" -p "$RPORT" --user "$RUSER" "$@"
  else
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning -h "$RHOST" -p "$RPORT" "$@"
  fi
}
PREFIX=$(sudo grep -E '^REDIS_PREFIX=' /etc/mknoon/relay-server.env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r' | xargs)
[ -z "$PREFIX" ] && PREFIX="relay:"
case "$PREFIX" in (*:) ;; (*) PREFIX="$PREFIX:";; esac

SVC_RAW=$(systemctl show relay-server -p ActiveEnterTimestamp --value)
SVC_START=$(date -u -d "$SVC_RAW" '+%Y-%m-%d %H:%M:%S')
echo "service active since: $SVC_START UTC"
sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "Starting relay-server" | tail -1

DEAD_PREFIXES=$(sudo journalctl -u relay-server --since "-48 hours" --no-pager \
  | sed -nE 's@.*Push to ([A-Za-z0-9]{20}) failed on attempt 1/3: (NotRegistered|Requested entity was not found).*@\1@p' \
  | sort -u)
echo "dead-token peer prefixes from journal: ${DEAD_PREFIXES:-<none>}"

FULL=""; KEYNAME=""
for P in $DEAD_PREFIXES; do
  for key in $(rcli --scan --pattern "${PREFIX}push:*"); do
    comp=${key#"${PREFIX}"push:}
    pid=$(python3 -c 'import base64,sys; s=sys.argv[1]; s+="="*(-len(s)%4); print(base64.urlsafe_b64decode(s).decode())' "$comp" 2>/dev/null) || continue
    case "$pid" in ("$P"*) FULL="$pid"; KEYNAME="$key"; break 2;; esac
  done
done

if [ -z "$FULL" ]; then
  NAT=$(sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "Removed invalid token for" | tail -3)
  if [ -n "$NAT" ]; then
    echo "no dead token left in redis, but natural evictions since deploy:"
    echo "$NAT"
    NPEER=$(printf '%s\n' "$NAT" | tail -1 | sed -nE 's/.*Removed invalid token for ([A-Za-z0-9]{20}).*/\1/p')
    RETR=$(sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "Push to ${NPEER}" | grep -a -c "retrying in")
    echo "retry lines for ${NPEER} since deploy: ${RETR:-0}"
    if [ "${RETR:-0}" = "0" ]; then echo "PREP=natural_eviction_proven"; exit 0; fi
    echo "PREP=natural_eviction_but_retries_present"; exit 1
  fi
  echo "PREP=no_dead_token"
  exit 1
fi

echo "dead-token source peer: ${FULL:0:20}… (key $KEYNAME)"
TOKEN=$(rcli GET "$KEYNAME" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Token"])')
if [ -z "$TOKEN" ]; then echo "PREP=token_parse_failed"; exit 1; fi
BKEY="${PREFIX}push:$(printf '%s' "$B" | base64 -w0 | tr '+/' '-_' | tr -d '=')"
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
rcli SET "$BKEY" "{\"Token\":\"$TOKEN\",\"Platform\":\"android\",\"UpdatedAt\":\"$NOW\"}" >/dev/null
echo "registered dead token for scratch peer at $BKEY"
echo "PREP=ok"
REMOTE
)
PREP_STATUS=$?
printf '%s\n' "$PREP_OUT" >> "$OUT"

case "$PREP_OUT" in
  *PREP=natural_eviction_proven*)
    log "TC-320-13=PASS (natural eviction since deploy, zero retry lines — synthetic probe unnecessary)"
    exit 0 ;;
  *PREP=ok*) ;;
  *)
    log "TC-320-13=FAIL (prep leg: no usable dead token — see result file)"
    exit 1 ;;
esac

log "--- probe leg (local): one ordinary chat store to the scratch peer via the production relay ---"
PROBE_OUT=$("$TP" 2>>"$OUT" <<EOF
{"cmd":"generate_identity"}
{"cmd":"start"}
{"cmd":"wait_relay","params":{"timeoutSec":30}}
{"cmd":"inbox_store_v1","params":{"peerId":"$B_PEER","text":"mknoon plan-320 TC-13 eviction probe"}}
{"cmd":"stop"}
EOF
)
printf '%s\n' "$PROBE_OUT" >> "$OUT"
if ! printf '%s' "$PROBE_OUT" | grep -q '"storeStatus":"stored"'; then
  log "probe store did not report stored — continuing to assert/cleanup leg anyway"
fi

log "--- waiting 12s for the async push dispatch + FCM round-trip ---"
sleep 12

log "--- assert leg (relay box): eviction line present, zero retries, key gone; cleanup ---"
ASSERT_OUT=$($SSH "$HOST" 'bash -s' "$B_PEER" <<'REMOTE'
set -u
B="$1"; B20=${B:0:20}
RAW=$(sudo grep -E '^REDIS_URL=' /etc/mknoon/relay-server.env | head -1 | cut -d= -f2-)
URL=$(printf '%s' "$RAW" | tr -d '"\r' | xargs)
REST=${URL#*://}
CREDS=""; HOSTPORT=$REST
if [[ "$REST" == *@* ]]; then CREDS=${REST%@*}; HOSTPORT=${REST##*@}; fi
HOSTPORT=${HOSTPORT%%/*}; RHOST=${HOSTPORT%%:*}; RPORT=${HOSTPORT##*:}
[ "$RPORT" = "$RHOST" ] && RPORT=6379
RUSER=""; RPASS=""
if [ -n "$CREDS" ]; then
  if [[ "$CREDS" == *:* ]]; then RUSER=${CREDS%%:*}; RPASS=${CREDS#*:}; else RPASS=$CREDS; fi
fi
if [[ "$RPASS" == *%* ]]; then RPASS=$(printf '%b' "${RPASS//%/\\x}"); fi
rcli() {
  if [ -n "$RUSER" ]; then
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning -h "$RHOST" -p "$RPORT" --user "$RUSER" "$@"
  else
    REDISCLI_AUTH="$RPASS" redis-cli --no-auth-warning -h "$RHOST" -p "$RPORT" "$@"
  fi
}
PREFIX=$(sudo grep -E '^REDIS_PREFIX=' /etc/mknoon/relay-server.env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"\r' | xargs)
[ -z "$PREFIX" ] && PREFIX="relay:"
case "$PREFIX" in (*:) ;; (*) PREFIX="$PREFIX:";; esac
SVC_RAW=$(systemctl show relay-server -p ActiveEnterTimestamp --value)
SVC_START=$(date -u -d "$SVC_RAW" '+%Y-%m-%d %H:%M:%S')

echo "--- journal lines for scratch peer ${B20} since service start ---"
sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "$B20" || echo "(none)"

EVICT=$(sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "Removed invalid token for ${B20}" | grep -a -c "reason=")
RETR=$(sudo journalctl -u relay-server --since "$SVC_START" --no-pager | grep -a "Push to ${B20}" | grep -a -c "retrying in")
B64=$(printf '%s' "$B" | base64 -w0 | tr '+/' '-_' | tr -d '=')
BKEY="${PREFIX}push:${B64}"
LEFT=$(rcli EXISTS "$BKEY")

echo "--- scratch cleanup ---"
for k in $(rcli --scan --pattern "${PREFIX}inbox:${B64}*") "$BKEY"; do
  rcli DEL "$k" >/dev/null && echo "deleted $k"
done

echo "evict_lines=${EVICT:-0} retry_lines=${RETR:-0} token_key_still_present=${LEFT:-?}"
if [ "${EVICT:-0}" -ge 1 ] && [ "${RETR:-0}" = "0" ] && [ "${LEFT:-1}" = "0" ]; then
  echo "TC-320-13=PASS"
else
  echo "TC-320-13=FAIL"
  exit 1
fi
REMOTE
)
ASSERT_STATUS=$?
printf '%s\n' "$ASSERT_OUT" >> "$OUT"

log "=== TC-320-13 verify finished $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
if [ "$ASSERT_STATUS" -eq 0 ] && printf '%s' "$ASSERT_OUT" | grep -q 'TC-320-13=PASS'; then
  log "RESULT: PASS"
  exit 0
fi
log "RESULT: FAIL (see $OUT)"
exit 1
