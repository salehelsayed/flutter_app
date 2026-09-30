#!/usr/bin/env bash
# Run as root on the production relay only after explicit approval.
set -euo pipefail

old_ip=13.60.250.19
new_ip=51.21.194.144
env_file=/etc/mknoon/relay-server.env

exec 9>/run/mknoon-r28-relay-ip.lock
if ! flock -n 9; then
  echo 'another relay IP update is running' >&2
  exit 1
fi

resolved=$(getent ahostsv4 mknoun.xyz | awk 'NR == 1 { print $1 }')
[[ "$resolved" == "$new_ip" ]] || {
  echo "DNS resolves to $resolved; expected $new_ip" >&2
  exit 1
}
systemctl is-active --quiet relay-server
curl --max-time 2 -fsS localhost:2112/metrics >/dev/null

configured=$(awk -F= '$1 == "RELAY_SERVER_IP" { print $2 }' "$env_file")
[[ "$configured" == "$old_ip" ]] || {
  echo "unexpected RELAY_SERVER_IP=$configured; no change made" >&2
  exit 1
}

backup_dir=/var/backups/mknoon-relay/r28-ip-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0700 "$backup_dir"
cp -p "$env_file" "$backup_dir/relay-server.env"
restore() {
  echo 'health check failed; restoring the relay env and restarting' >&2
  cp -p "$backup_dir/relay-server.env" "$env_file"
  systemctl restart relay-server
  for attempt in {1..45}; do
    if systemctl is-active --quiet relay-server &&
        curl --max-time 2 -fsS localhost:2112/metrics >/dev/null 2>&1; then
      echo 'rollback relay health check passed' >&2
      return
    fi
    sleep 2
  done
  echo 'rollback relay health check failed' >&2
}
trap restore ERR

python3 - "$env_file" "$old_ip" "$new_ip" <<'PY'
import os
from pathlib import Path
import sys
import tempfile

path = Path(sys.argv[1])
old, new = sys.argv[2:]
before = path.read_text()
lines = before.splitlines(keepends=True)
matches = [i for i, line in enumerate(lines) if line.startswith('RELAY_SERVER_IP=')]
if len(matches) != 1 or lines[matches[0]].strip() != f'RELAY_SERVER_IP={old}':
    raise RuntimeError('unexpected relay IP setting')
lines[matches[0]] = f'RELAY_SERVER_IP={new}\n'
stat = path.stat()
fd, temporary = tempfile.mkstemp(prefix='.r28-relay-ip-', dir=path.parent)
try:
    with os.fdopen(fd, 'w') as stream:
        stream.writelines(lines)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, stat.st_mode & 0o7777)
    os.chown(temporary, stat.st_uid, stat.st_gid)
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY

systemctl restart relay-server
for attempt in {1..45}; do
  if systemctl is-active --quiet relay-server &&
      curl --max-time 2 -fsS localhost:2112/metrics >/dev/null 2>&1; then
    trap - ERR
    echo "relay healthy; RELAY_SERVER_IP=$new_ip; backup=$backup_dir"
    exit 0
  fi
  sleep 2
done
false
