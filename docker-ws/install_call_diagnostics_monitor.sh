#!/bin/bash
# Run as root after the diagnostics relay and operator are healthy.
set -euo pipefail
MONITOR=${1:?monitor script path required}
python3 "$MONITOR" --help >/dev/null
install -m 0700 "$MONITOR" /usr/local/bin/monitor_call_diagnostics.py
install -d -m 0700 /var/lib/mknoon/call-diagnostics-report
cat >/etc/systemd/system/call-diagnostics-monitor.service <<'EOF'
[Unit]
Description=MKnoon protected call diagnostics aggregate and alert transitions
After=relay-server.service

[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/bin/python3 /usr/local/bin/monitor_call_diagnostics.py
TimeoutStartSec=50
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/mknoon/call-diagnostics-report
StandardOutput=journal
StandardError=journal
EOF
cat >/etc/systemd/system/call-diagnostics-monitor.timer <<'EOF'
[Unit]
Description=Check MKnoon call diagnostic rates every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5
Unit=call-diagnostics-monitor.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl start call-diagnostics-monitor.service
systemctl enable --now call-diagnostics-monitor.timer
systemctl is-active --quiet call-diagnostics-monitor.timer
test -s /var/lib/mknoon/call-diagnostics-report/latest.json
echo 'Protected aggregate report and journal alert monitor enabled.'
