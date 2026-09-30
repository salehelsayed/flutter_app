#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/install_r24.sh" \
  > "$H/install_r24.out" 2>&1 < /dev/null &
echo "r24 install launched pid $!"
