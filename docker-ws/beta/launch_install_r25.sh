#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/install_r25.sh" \
  > "$H/install_r25.out" 2>&1 < /dev/null &
echo "r25 install launched pid $!"
