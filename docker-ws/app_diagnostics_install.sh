#!/usr/bin/env bash
# Run on the relay only after candidate review. Does not restart relay-server.
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo 'Run as root on the reviewed relay host.' >&2
  exit 1
fi
backup_dir="/var/backups/mknoon-app-diagnostics/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_dir"
for owned_file in /usr/local/bin/app_diagnostics.py /etc/systemd/system/relay-server.service.d/app-diagnostics.conf /etc/systemd/system/mknoon-app-diagnostics-monitor.service /etc/systemd/system/mknoon-app-diagnostics-monitor.timer; do
  if [[ -f "$owned_file" ]]; then cp -a --parents "$owned_file" "$backup_dir/"; fi
done
readlink /usr/local/lib/mknoon-app-diagnostics/current > "$backup_dir/previous-operator-target.txt" || true
systemctl is-enabled mknoon-app-diagnostics-monitor.timer > "$backup_dir/previous-timer-enabled.txt" 2>/dev/null || true
systemctl is-active mknoon-app-diagnostics-monitor.timer > "$backup_dir/previous-timer-active.txt" 2>/dev/null || true
bundle_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
service_user="${APP_DIAGNOSTICS_SERVICE_USER:-$(systemctl show relay-server.service --value --property=User)}"
service_user="${service_user:-root}"
service_group="$(id -gn "$service_user")"
install -d -m 0700 -o "$service_user" -g "$service_group" /var/lib/mknoon/app-diagnostics
# Operators and schema are an atomic pair via a versioned protected directory.
release_hash="$(sha256sum "$bundle_dir/app_diagnostics.py" "$bundle_dir/app_diagnostics_schema_v1.json" "$bundle_dir/app_diagnostics_monitor.py" | sha256sum | cut -d ' ' -f 1)"
release_dir="/usr/local/lib/mknoon-app-diagnostics/$release_hash"
install -d -m 0755 "$release_dir"
install -m 0755 "$bundle_dir/app_diagnostics.py" "$release_dir/app_diagnostics.py"
install -m 0644 "$bundle_dir/app_diagnostics_schema_v1.json" "$release_dir/app_diagnostics_schema_v1.json"
install -m 0755 "$bundle_dir/app_diagnostics_monitor.py" "$release_dir/app_diagnostics_monitor.py"
python3 "$release_dir/app_diagnostics.py" --help >/dev/null
python3 "$release_dir/app_diagnostics_monitor.py" --help >/dev/null
ln -sfn "$release_dir" /usr/local/lib/mknoon-app-diagnostics/current.next
mv -Tf /usr/local/lib/mknoon-app-diagnostics/current.next /usr/local/lib/mknoon-app-diagnostics/current
cat > /usr/local/bin/app_diagnostics.py.next <<'PY'
#!/usr/bin/env python3
import os
import sys
os.execv(sys.executable, [sys.executable, '/usr/local/lib/mknoon-app-diagnostics/current/app_diagnostics.py', *sys.argv[1:]])
PY
chmod 0755 /usr/local/bin/app_diagnostics.py.next
mv /usr/local/bin/app_diagnostics.py.next /usr/local/bin/app_diagnostics.py
install -d -m 0755 /etc/systemd/system/relay-server.service.d
cat > /etc/systemd/system/relay-server.service.d/app-diagnostics.conf.next <<'CONF'
[Service]
Environment=APP_DIAGNOSTICS_DIR=/var/lib/mknoon/app-diagnostics
Environment=APP_DIAGNOSTICS_MAX_BYTES=134217728
CONF
chmod 0644 /etc/systemd/system/relay-server.service.d/app-diagnostics.conf.next
mv /etc/systemd/system/relay-server.service.d/app-diagnostics.conf.next /etc/systemd/system/relay-server.service.d/app-diagnostics.conf
install -d -m 0700 -o "$service_user" -g "$service_group" /var/lib/mknoon/app-diagnostics-monitor
cat > /etc/systemd/system/mknoon-app-diagnostics-monitor.service.next <<UNIT
[Unit]
Description=Private Mknoon app diagnostic snapshot and local alerts
After=relay-server.service
[Service]
Type=oneshot
User=$service_user
Group=$service_group
UMask=0077
ExecStart=/usr/bin/python3 /usr/local/lib/mknoon-app-diagnostics/current/app_diagnostics_monitor.py
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/var/lib/mknoon/app-diagnostics
ReadWritePaths=/var/lib/mknoon/app-diagnostics-monitor
TimeoutStartSec=120
MemoryMax=768M
Nice=10
UNIT
cat > /etc/systemd/system/mknoon-app-diagnostics-monitor.timer.next <<'TIMER'
[Unit]
Description=Update private app diagnostic monitor every five minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=15s
Persistent=true
Unit=mknoon-app-diagnostics-monitor.service
[Install]
WantedBy=timers.target
TIMER
chmod 0644 /etc/systemd/system/mknoon-app-diagnostics-monitor.service.next /etc/systemd/system/mknoon-app-diagnostics-monitor.timer.next
mv /etc/systemd/system/mknoon-app-diagnostics-monitor.service.next /etc/systemd/system/mknoon-app-diagnostics-monitor.service
mv /etc/systemd/system/mknoon-app-diagnostics-monitor.timer.next /etc/systemd/system/mknoon-app-diagnostics-monitor.timer
systemctl daemon-reload
systemctl enable --now mknoon-app-diagnostics-monitor.timer
systemctl start mknoon-app-diagnostics-monitor.service
echo "App operator/monitor prepared; installer backup: $backup_dir"
echo 'Relay binary replacement/restart remains a separate reviewed step.' 
