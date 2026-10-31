#!/bin/bash
# VC-023 (owner approved): stop coturn on the Hetzner TEST relay for a short window. Arms a systemd safety timer first that
# starts coturn again after 9 minutes even if the operator never runs vcC_coturn_start.sh.
#   python3 docker-ws/hetzner_ssh.py < docker-ws/vcC_coturn_stop.sh
systemctl list-units --all --plain --no-legend | awk '{print $1}' | grep -x coturn.service || { echo "REFUSED: coturn.service not found"; exit 2; }
systemd-run --unit=vcc-coturn-safety-start --on-active=9min /bin/systemctl start coturn.service 2>&1 | tail -1
systemctl list-timers --all --no-legend | grep -c vcc-coturn-safety-start | sed 's/^/safety_timer_count=/'
echo "pre_state=$(systemctl is-active coturn.service)"
systemctl stop coturn.service
echo "STOP_UTC=$(date -u +%FT%T.%3NZ) state_after=$(systemctl is-active coturn.service)"
