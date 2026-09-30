#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_r23.sh" \
  > "$H/build_r23.out" 2>&1 < /dev/null &
echo "r23 build launched pid $!"
