#!/bin/bash
# Read-only: full args of emulator qemu processes (audio flags check).
ps -axo pid=,args= | grep qemu-system | grep -v grep | grep -o -E "^ *[0-9]+|-avd [^ ]+|-port [0-9]+|-no-audio|-no-window|audio[^ ]*"
