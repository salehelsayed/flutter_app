#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_r2fix_validate.sh" "$@" \
  > "$H/run_r2fix_validate.out" 2>&1 < /dev/null &
echo "r2fix validate launched pid $!"
