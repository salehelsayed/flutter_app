#!/bin/bash
# List running emulator/qemu processes (pid, avd) on the Mac. Read-only.
ps -axo pid,command | grep -E '[q]emu-system|[e]mulator -avd' | sed -E 's/^ *([0-9]+) .*-avd ([^ ]+).*/\1 \2/'
