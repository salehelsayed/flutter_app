#!/bin/bash
# Read-only: inspect the cee8bcf6 group inbox entries around 19:30Z to
# determine whether the two un-fanned stores were group_reaction envelopes.
# Prints only metadata fields (type/kind/timestamps/from), never ciphertext.
# Result: docker-ws/relay_group_inbox_inspect_309_result.txt
set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_DIR/se.pem"
OUT="$REPO_DIR/docker-ws/relay_group_inbox_inspect_309_result.txt"
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
if [[ "$RPASS" == *%* ]]; then
  RPASS=$(printf '%b' "${RPASS//%/\\x}")
fi
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
    cee8bcf6*|9bc055cc*|83d6d5e6*)
      echo
      echo "== group ${g:0:13}... type=$(rcli TYPE "$gid") len=$(rcli LLEN "$gid" 2>/dev/null || rcli ZCARD "$gid" 2>/dev/null) =="
      # entries are JSON: {from, message(escaped envelope), timestamp, id}
      # print per-entry: timestamp, from(20), and the envelope's type/kind/payloadType/action WITHOUT ciphertext
      rcli LRANGE "$gid" 0 -1 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        outer = json.loads(line)
    except Exception:
        continue
    ts = outer.get("timestamp")
    frm = str(outer.get("from", ""))[:20]
    try:
        env = json.loads(outer.get("message", "{}"))
    except Exception:
        env = {}
    keys = {k: env.get(k) for k in ("type", "kind", "payloadType", "version", "keyEpoch", "messageId") if k in env}
    has_ext = "notificationExtension" in env
    ext_action = ""
    if has_ext and isinstance(env.get("notificationExtension"), dict):
        ext_action = env["notificationExtension"].get("action", "")
        ext_recips = env["notificationExtension"].get("notificationRecipientTransportPeerIds", [])
        ext_recips = [str(r)[:20] for r in ext_recips] if isinstance(ext_recips, list) else ext_recips
    else:
        ext_recips = None
    import datetime
    tss = datetime.datetime.utcfromtimestamp(ts/1000).isoformat() if isinstance(ts, (int, float)) else str(ts)
    print(f"  ts={tss} from={frm} meta={keys} ext={has_ext} action={ext_action} notifRecipients={ext_recips}")
'
      ;;
  esac
done
REMOTE

echo "wrote $OUT"
