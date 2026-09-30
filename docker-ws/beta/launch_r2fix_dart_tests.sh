#!/bin/bash
# Start run_r2fix_dart_tests.sh detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_r2fix_dart_tests.sh" \
  > "$H/run_r2fix_dart_tests.out" 2>&1 < /dev/null &
echo "r2fix dart tests launched pid $!"
