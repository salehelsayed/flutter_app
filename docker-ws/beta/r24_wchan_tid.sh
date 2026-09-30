#!/bin/bash
# Kernel wait channel of one app thread (run-as, debug build). Usage: r24_wchan_tid.sh <tid>
. "$(dirname "$0")/beta_env.sh"
P=$($ADB shell pidof $PKG | tr -d '\r'); T=$1
echo "app $P tid $T: $($ADB shell run-as $PKG cat /proc/$P/task/$T/comm 2>&1 | tr -d '\r')"
echo "wchan: $($ADB shell run-as $PKG cat /proc/$P/task/$T/wchan 2>&1 | tr -d '\r')"
echo "syscall: $($ADB shell run-as $PKG cat /proc/$P/task/$T/syscall 2>&1 | tr -d '\r')"
$ADB shell run-as $PKG cat /proc/$P/task/$T/status 2>&1 | grep -E "State|voluntary"
echo "--- codec service pid 566: $($ADB shell ps -o NAME= -p 566 | tr -d '\r')"
