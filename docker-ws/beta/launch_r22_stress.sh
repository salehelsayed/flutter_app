#!/bin/bash
# launch_r22_stress.sh <label> <seconds> [maxcrash] [quiet] [update] [churn] : detached run of r22_stress.sh
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/r22_stress.sh" "$@" \
  > "$H/r22_stress.out" 2>&1 < /dev/null &
echo "r22 stress launched pid $! args: $*"
