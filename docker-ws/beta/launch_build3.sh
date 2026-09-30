#!/bin/bash
# Start build_beta_fixed3.sh <fix sha> detached from the host bridge; return at once.
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/build_beta_fixed3.sh" "$@" \
  > "$H/build_beta_fixed3.out" 2>&1 < /dev/null &
echo "build launched pid $!"
