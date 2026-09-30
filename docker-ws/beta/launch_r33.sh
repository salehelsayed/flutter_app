#!/bin/bash
# launch_r33.sh <build|install|validate> [args]: detached run of the matching R2-10 script.
# Output: docker-ws/beta/<script>.out
H="$(cd "$(dirname "$0")" && pwd)"
case "$1" in
  build) S=build_r33.sh ;;
  install) S=install_r33.sh ;;
  validate) S=run_r33_validate.sh ;;
  *) echo "usage: launch_r33.sh <build|install|validate> [args]"; exit 1 ;;
esac
shift
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/$S" "$@" \
  > "$H/${S%.sh}.out" 2>&1 < /dev/null &
echo "$S launched pid $! args: ${*:-none}"
