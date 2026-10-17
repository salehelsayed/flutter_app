#!/bin/bash
# Stop ONE disposable emulator (qemu) by exact PID, only after verifying the PID is qemu running the named AVD.
#   host-run bash docker-ws/kill_exact_qemu.sh <pid> <avd-name>
set -u
PID="${1:?pid}"; AVD="${2:?avd}"
[[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: pid must be numeric" >&2; exit 2; }
NAME="$(ps -o comm= -p "$PID" 2>/dev/null)"
case "$NAME" in
  */qemu-system-*|qemu-system-*) ;;
  *) echo "refused: pid $PID is not qemu" >&2; exit 2 ;;
esac
ARG="$(ps -o command= -p "$PID" | tr ' ' '\n' | awk 'f {print; exit} $0=="-avd" {f=1}')"
[ "$ARG" = "$AVD" ] || { echo "refused: pid $PID runs avd '$ARG', not '$AVD'" >&2; exit 2; }
kill "$PID" && echo "sent TERM to qemu $PID ($AVD)"
for i in 1 2 3 4 5 6 7 8 9 10; do sleep 2; ps -p "$PID" >/dev/null 2>&1 || { echo "gone"; exit 0; }; done
kill -KILL "$PID" && echo "sent KILL to qemu $PID ($AVD)"
sleep 2; ps -p "$PID" >/dev/null 2>&1 && echo "still running" || echo "gone"
