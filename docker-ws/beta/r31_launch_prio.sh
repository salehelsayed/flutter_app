#!/bin/bash
# Detached run of r31_qemu_prio.sh for N seconds (default 1500).
H="$(cd "$(dirname "$0")" && pwd)"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/r31_qemu_prio.sh" "${1:-1500}" > /dev/null 2>&1 < /dev/null &
echo "prio sampler pid $!"
