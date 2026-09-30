#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/install_r2fix_android.sh" \
  > "$H/install_r2fix_android.out" 2>&1 < /dev/null &
echo "r2fix install launched pid $!"
