#!/bin/bash
# Start build_android_b5.sh detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_android_b5.sh" \
  > "$H/build_android_b5.out" 2>&1 < /dev/null &
echo "b5 build launched pid $!"
