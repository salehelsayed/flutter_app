#!/bin/bash
# VC-023: start coturn on the Hetzner TEST relay again, report is-active, and disarm the safety timer from vcC_coturn_stop.sh.
#   python3 docker-ws/hetzner_ssh.py < docker-ws/vcC_coturn_start.sh
systemctl start coturn.service
echo "START_UTC=$(date -u +%FT%T.%3NZ)"
sleep 3
echo "is_active=$(systemctl is-active coturn.service) since=$(systemctl show -p ActiveEnterTimestamp --value coturn.service)"
systemctl stop vcc-coturn-safety-start.timer 2>/dev/null; systemctl reset-failed vcc-coturn-safety-start.service 2>/dev/null
echo "safety_timer_left=$(systemctl list-timers --all --no-legend | grep -c vcc-coturn-safety-start)"
