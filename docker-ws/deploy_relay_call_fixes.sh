#!/bin/bash
# Run on the relay as root after host checks, artifact upload, and TURN TLS proof.
# Usage: sudo bash script.sh /tmp/relay-artifact <expected-sha256>
set -euo pipefail
ARTIFACT=${1:?binary path required}
EXPECTED=${2:?expected sha256 required}
ACTUAL=$(sha256sum "$ARTIFACT" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'artifact digest mismatch' >&2; exit 1; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="/var/backups/mknoon-relay/$STAMP"
install -d -m 0700 "$BACKUP"
cp -p /usr/local/bin/relay-server "$BACKUP/relay-server"
cp -p /etc/mknoon/relay-server.env "$BACKUP/relay-server.env"
rollback() {
  echo "deployment failed; restoring $BACKUP" >&2
  install -m 0755 "$BACKUP/relay-server" /usr/local/bin/relay-server.rollback
  mv /usr/local/bin/relay-server.rollback /usr/local/bin/relay-server
  cp -p "$BACKUP/relay-server.env" /etc/mknoon/relay-server.env
  systemctl restart relay-server
}
trap rollback ERR
python3 - <<'PY'
from pathlib import Path
import os, stat, tempfile
p=Path('/etc/mknoon/relay-server.env')
before=p.read_text(); lines=before.splitlines(); found=False
for i,line in enumerate(lines):
    if line.startswith('TURN_CREDENTIAL_URLS='):
        urls=line.split('=',1)[1].strip().strip('"').strip("'").split(',')
        tls='turns:mknoun.xyz:5349?transport=tcp'
        if tls not in urls: urls.append(tls)
        lines[i]='TURN_CREDENTIAL_URLS='+','.join(urls); found=True
if not found: raise RuntimeError('Existing TURN credential URL config is required')
st=p.stat(); fd,tmp=tempfile.mkstemp(prefix='.relay-call-fix-',dir=p.parent)
try:
    with os.fdopen(fd,'w') as f: f.write('\n'.join(lines)+'\n')
    os.chmod(tmp,stat.S_IMODE(st.st_mode)); os.chown(tmp,st.st_uid,st.st_gid)
    os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print('Existing TURN URLs preserved; verified TLS endpoint appended.')
PY
install -m 0755 "$ARTIFACT" /usr/local/bin/relay-server.next
mv /usr/local/bin/relay-server.next /usr/local/bin/relay-server
systemctl restart relay-server
for attempt in $(seq 1 20); do
  if systemctl is-active --quiet relay-server && curl --max-time 2 -fsS localhost:2112/metrics >/dev/null; then
    echo "deployed_sha256=$ACTUAL backup=$BACKUP"
    trap - ERR
    exit 0
  fi
  sleep 1
done
false
