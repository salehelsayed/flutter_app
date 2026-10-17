#!/bin/bash
# Read-only: state, CPU and age of the Mac's emulator (qemu) processes.
#   host-run bash docker-ws/emu_state.sh
set -u
ps -axo pid=,state=,pcpu=,etime=,comm= | awk '$5 ~ /qemu|emulator/ {n=split($5,p,"/"); printf "%7s %4s %6s %12s %s\n", $1, $2, $3, $4, p[n]}'
