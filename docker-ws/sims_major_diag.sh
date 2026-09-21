#!/bin/bash
# Why is the sims gate blocked? Read-only: lsof + a stack sample.
set -uo pipefail
pid="$(pgrep -f 'tool/sims/sims.dart' 2>/dev/null | head -1)"
if [ -z "$pid" ]; then echo "no sims.dart process"; exit 0; fi
echo "pid=$pid"
ps -o pid,ppid,etime,time,%cpu,stat,command -p "$pid" 2>/dev/null | cut -c1-200
echo "--- parent chain"
p="$pid"
for i in 1 2 3 4 5; do
  pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  [ -z "$pp" ] || [ "$pp" = "0" ] && break
  ps -o pid,ppid,stat,command -p "$pp" 2>/dev/null | tail -1 | cut -c1-160
  p="$pp"
done
echo "--- sockets / tty / pipes"
lsof -p "$pid" -nP 2>/dev/null | grep -E 'TCP|UDP|PIPE|CHR|unix' | head -25
echo "--- interesting open files"
lsof -p "$pid" -nP 2>/dev/null | grep -vE '\.dylib|\.framework|/usr/lib|/System/' | head -25
echo "--- stack sample (3s)"
sample "$pid" 3 -mayDie -file /tmp/sims_sample.txt >/dev/null 2>&1
if [ -f /tmp/sims_sample.txt ]; then
  sed -n '/Call graph/,/Binary Images/p' /tmp/sims_sample.txt | head -70
else
  echo "(sample unavailable)"
fi
