#!/bin/bash
# Read-only: list running emulator/qemu processes with their AVD and port.
ps -axo pid,command | awk '/qemu-system|emulator\/emulator/ && !/awk/ {print $1, substr($0, index($0,"-avd"), 40)}'
