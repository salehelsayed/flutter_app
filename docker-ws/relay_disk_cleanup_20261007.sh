#!/bin/bash
# User-approved 2026-10-07: free disk on the production relay.
# Run: RELAY_SSH_HOST=51.21.194.144 python3 docker-ws/relay_disk_cleanup_20261007.sh
# 1) delete old relay binary backups, keeping the live binary + the 3 newest backups
# 2) cap the systemd journal at 500 MB and vacuum it
# 3) delete the rotated /var/log/syslog.1
# Nothing here restarts relay-server.
set -u
cd /usr/local/bin || exit 1
echo "before: $(df -h / | awk 'NR==2 {print $4" free, "$5" used"}')"
exe=$(sudo readlink /proc/$(systemctl show -p MainPID --value relay-server)/exe)
[ "$exe" = /usr/local/bin/relay-server ] || { echo "ABORT: running exe is $exe"; exit 1; }

keep="relay-server.pre-1.10.9-20261003T095020Z relay-server.pre-1.10.7-20260912T151514Z relay-server.before-ipv6-20260907"
for k in $keep; do [ -f "$k" ] || { echo "ABORT: keep file $k missing"; exit 1; }; done
n=0
for f in relay-server.*; do
  [ -f "$f" ] || continue
  case " $keep " in *" $f "*) continue ;; esac
  if sudo grep -rqF "$f" /etc/systemd/system /etc/cron* 2>/dev/null; then echo "SKIP (referenced): $f"; continue; fi
  sudo rm -f -- "$f" && n=$((n+1))
done
echo "deleted $n relay backups; left: $(ls relay-server* | tr '\n' ' ')"

sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=500M\n' | sudo tee /etc/systemd/journald.conf.d/50-size-cap.conf >/dev/null
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-size=500M 2>&1 | tail -1
sudo journalctl --disk-usage

sudo rm -f /var/log/syslog.1 && echo "deleted /var/log/syslog.1"

echo "after: $(df -h / | awk 'NR==2 {print $4" free, "$5" used"}')"
echo "relay-server: $(systemctl is-active relay-server) restarts=$(systemctl show -p NRestarts --value relay-server) since $(systemctl show -p ActiveEnterTimestamp --value relay-server)"
sleep 65; sudo journalctl -u relay-server --since "-2min" --no-pager -o cat | grep STATS | tail -1
