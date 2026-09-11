#!/usr/bin/env bash
set -euo pipefail

artifact=${1:?uploaded binary required}
expected_sha=${2:?uploaded SHA-256 required}
expected_previous_sha=${3:?reviewed live SHA-256 required}
actual_sha=$(sha256sum "$artifact" | awk '{print $1}')
previous_sha=$(sha256sum /usr/local/bin/relay-server | awk '{print $1}')
[[ "$actual_sha" == "$expected_sha" ]] || { echo 'Uploaded binary digest mismatch' >&2; exit 1; }
[[ "$previous_sha" == "$expected_previous_sha" ]] || { echo 'Live relay changed since review; deployment stopped' >&2; exit 1; }

backup_dir="/var/backups/mknoon-relay/history-fix-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_dir"
cp -p /usr/local/bin/relay-server "$backup_dir/relay-server"
rollback() {
  trap - ERR
  echo "Deployment failed; restoring $backup_dir/relay-server" >&2
  install -m 0755 "$backup_dir/relay-server" /usr/local/bin/relay-server.history-rollback
  mv /usr/local/bin/relay-server.history-rollback /usr/local/bin/relay-server
  systemctl restart relay-server
}
trap rollback ERR
install -m 0755 "$artifact" /usr/local/bin/relay-server.history-next
mv /usr/local/bin/relay-server.history-next /usr/local/bin/relay-server
systemctl restart relay-server
for attempt in $(seq 1 20); do
  if systemctl is-active --quiet relay-server &&
     curl --max-time 2 -fsS localhost:2112/metrics | grep '^relay_backend_durable 1$' >/dev/null; then
    installed_sha=$(sha256sum /usr/local/bin/relay-server | awk '{print $1}')
    [[ "$installed_sha" == "$expected_sha" ]]
    trap - ERR
    printf 'deployed_sha256=%s\nprevious_sha256=%s\nbackup=%s\n' "$installed_sha" "$previous_sha" "$backup_dir"
    date -u '+deployed_at=%Y-%m-%dT%H:%M:%SZ'
    systemctl show relay-server -p ActiveState -p MainPID -p ExecMainStartTimestamp
    exit 0
  fi
  sleep 1
done
false
