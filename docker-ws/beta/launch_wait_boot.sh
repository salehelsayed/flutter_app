#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/wait_boot_then_rerun.sh" > /dev/null 2>&1 < /dev/null &
echo "launched pid $!"
