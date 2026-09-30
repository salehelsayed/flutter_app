#!/bin/bash
# Start build_ios_inplace.sh [variant ...] detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_ios_inplace.sh" "$@" \
  > "$H/build_ios_inplace.out" 2>&1 < /dev/null &
echo "ios build launched pid $!"
