#!/bin/bash
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_r24_dart_tests.sh" \
  > "$H/run_r24_dart_tests.out" 2>&1 < /dev/null &
echo "r24 dart tests launched pid $!"
