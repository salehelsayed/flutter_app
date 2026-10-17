#!/bin/bash
# Read-only: each qemu process's priority, nice and CPU, plus its thread count by priority (4 = throttled by macOS).
#   host-run bash docker-ws/qemu_prio_now.sh
for p in $(ps -axo pid=,comm= | awk '$2 ~ /qemu-system/ {print $1}'); do
  avd=$(ps -o command= -p "$p" | tr ' ' '\n' | awk 'f {print; exit} $0=="-avd" {f=1}')
  th=$(ps -M -p "$p" | awk 'NR==2 {print $6} NR>2 {print $4}' | sort | uniq -c | sort -rn | awk '{printf "%s:%s ", $2, $1}')
  echo "pid=$p avd=$avd [pri,nice,cpu]=$(ps -o pri=,nice=,%cpu= -p "$p" | tr -s ' ') threads_by_pri=[$th]"
done
