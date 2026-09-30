#!/bin/bash
# Read-only: what Microsoft Defender is doing (health/scan state via the mdatp CLI, open files if permitted).
M=$(command -v mdatp || echo /usr/local/bin/mdatp)
echo "mdatp: $M"
$M health 2>&1 | grep -iE 'real_time_protection_enabled|real_time_protection_subsystem|scan|definitions_updated |definitions_status|passive_mode|behavior_monitoring|full_disk_access|engine_version|app_version|healthy' | head -20
echo "--- scan list:"; $M scan list 2>&1 | head -10
echo "--- exclusions:"; $M exclusion list 2>&1 | head -20
for n in wdavdaemon_unprivileged wdavdaemon_enterprise; do
  p=$(pgrep -f "$n" | head -1); echo "--- $n pid=$p user=$(ps -o user= -p $p) cpu=$(ps -o pcpu= -p $p)"
  lsof -p "$p" 2>&1 | awk '$4 ~ /[0-9]+[rwu]/ && $5=="REG" {print $9}' | grep -vE '^/(System|usr|Library/Application Support/Microsoft|Applications/Microsoft)' | head -15
done
