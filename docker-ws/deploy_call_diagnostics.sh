#!/bin/bash
# Run on the relay as root after tests. Keeps the current signaling/TURN config.
# Usage: sudo bash deploy_call_diagnostics.sh /tmp/relay-artifact <sha256> /tmp/call_diagnostics.py
set -euo pipefail
ARTIFACT=${1:?binary path required}
EXPECTED=${2:?expected sha256 required}
OPERATOR=${3:?operator script path required}
ACTUAL=$(sha256sum "$ARTIFACT" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'artifact digest mismatch' >&2; exit 1; }
python3 "$OPERATOR" --help >/dev/null
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="/var/backups/mknoon-relay/diagnostics-$STAMP"
install -d -m 0700 "$BACKUP"
cp -p /usr/local/bin/relay-server "$BACKUP/relay-server"
cp -p /etc/mknoon/relay-server.env "$BACKUP/relay-server.env"
if [ -f /usr/local/bin/call_diagnostics.py ]; then
  cp -p /usr/local/bin/call_diagnostics.py "$BACKUP/call_diagnostics.py"
fi
rollback() {
  echo "deployment failed; restoring $BACKUP" >&2
  install -m 0755 "$BACKUP/relay-server" /usr/local/bin/relay-server.rollback
  mv /usr/local/bin/relay-server.rollback /usr/local/bin/relay-server
  cp -p "$BACKUP/relay-server.env" /etc/mknoon/relay-server.env
  if [ -f "$BACKUP/call_diagnostics.py" ]; then
    install -m 0700 "$BACKUP/call_diagnostics.py" /usr/local/bin/call_diagnostics.py
  fi
  systemctl restart relay-server
}
trap rollback ERR
SERVICE_USER=$(systemctl show relay-server -p User --value)
SERVICE_GROUP=$(systemctl show relay-server -p Group --value)
SERVICE_USER=${SERVICE_USER:-root}
SERVICE_GROUP=${SERVICE_GROUP:-$(id -gn "$SERVICE_USER")}
install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_GROUP" /var/lib/mknoon/call-diagnostics
python3 - <<'PY'
from pathlib import Path
import os, stat, tempfile
p = Path('/etc/mknoon/relay-server.env')
lines = [line for line in p.read_text().splitlines() if not line.startswith('CALL_DIAGNOSTICS_DIR=')]
lines.append('CALL_DIAGNOSTICS_DIR=/var/lib/mknoon/call-diagnostics')
st = p.stat()
fd, temporary = tempfile.mkstemp(prefix='.relay-diagnostics-', dir=p.parent)
try:
    with os.fdopen(fd, 'w') as f:
        f.write('\n'.join(lines) + '\n')
        f.flush()
        os.fsync(f.fileno())
    os.chmod(temporary, stat.S_IMODE(st.st_mode))
    os.chown(temporary, st.st_uid, st.st_gid)
    os.replace(temporary, p)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
install -m 0700 "$OPERATOR" /usr/local/bin/call_diagnostics.py
install -m 0755 "$ARTIFACT" /usr/local/bin/relay-server.next
mv /usr/local/bin/relay-server.next /usr/local/bin/relay-server
systemctl restart relay-server
for attempt in $(seq 1 20); do
  if systemctl is-active --quiet relay-server && curl --max-time 2 -fsS localhost:2112/metrics >"$BACKUP/metrics-after.txt" && grep -q '^relay_call_diagnostics_storage_ready 1$' "$BACKUP/metrics-after.txt"; then
    echo "deployed_sha256=$ACTUAL backup=$BACKUP diagnostics_dir=/var/lib/mknoon/call-diagnostics"
    trap - ERR
    exit 0
  fi
  sleep 1
done
false
