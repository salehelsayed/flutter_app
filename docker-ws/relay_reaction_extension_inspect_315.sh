#!/bin/bash
# Read-only: print the FULL notification extension identity fields (reactor,
# target message, replay recipients) of the two empty-nomination reaction
# envelopes in group cee8bcf6, plus each stored message's sender identity keys,
# to decide roster-gap vs self-target. No ciphertext, signatures, or tokens.
# Result: docker-ws/relay_reaction_extension_inspect_315_result.txt
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_reaction_extension_inspect_315_result.txt"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"

$SSH 'bash -s' > "$OUT" 2>&1 <<'REMOTE'
echo "=== generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
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
echo "ping: $(rcli PING)"

for gid in $(rcli --scan --pattern 'relay:ginbox:*' | grep -v idseq); do
  comp=${gid#relay:ginbox:}
  pad=$comp
  case $(( ${#comp} % 4 )) in 2) pad="${comp}==";; 3) pad="${comp}=";; esac
  g=$(printf '%s' "$pad" | tr '_-' '/+' | base64 -d 2>/dev/null)
  case "$g" in
    cee8bcf6*)
      echo; echo "== group ${g} =="
      rcli LRANGE "$gid" 0 -1 | python3 -c '
import sys, json, datetime
def t(v, n=20):
    return str(v)[:n] if v is not None else None
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        outer = json.loads(line)
    except Exception:
        continue
    ts = outer.get("timestamp")
    tss = datetime.datetime.fromtimestamp(ts/1000, datetime.timezone.utc).isoformat() if isinstance(ts, (int, float)) else str(ts)
    try:
        env = json.loads(outer.get("message", "{}"))
    except Exception:
        env = {}
    base = {
        "ts": tss,
        "outer_from": t(outer.get("from")),
        "outer_recipients": [t(r) for r in (outer.get("recipientPeerIds") or [])] or None,
        "kind": env.get("kind"),
        "type": env.get("type"),
        "payloadType": env.get("payloadType"),
        "messageId": env.get("messageId"),
        "senderPeerId": t(env.get("senderPeerId")),
        "senderTransportPeerId": t(env.get("senderTransportPeerId")),
        "env_recipients": [t(r) for r in (env.get("recipientPeerIds") or [])] or None,
    }
    ext = env.get("notificationExtension")
    if isinstance(ext, dict):
        base["ext"] = {
            "action": ext.get("action"),
            "transitionId": t(ext.get("transitionId"), 44),
            "targetMessageId": ext.get("targetMessageId"),
            "reactorPeerId": t(ext.get("reactorPeerId")),
            "reactorTransportPeerId": t(ext.get("reactorTransportPeerId")),
            "notificationRecipientTransportPeerIds": [t(r) for r in (ext.get("notificationRecipientTransportPeerIds") or [])],
        }
    print(json.dumps(base, indent=1))
'
      ;;
  esac
done
REMOTE

echo "wrote $OUT"
