#!/bin/bash
# Start build_android_b8.sh detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_android_b8.sh" \
  > "$H/build_android_b8.out" 2>&1 < /dev/null &
echo "b8 build launched pid $!"
