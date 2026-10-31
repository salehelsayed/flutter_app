#!/bin/bash
# Read-only: lock files of one AVD and any running qemu processes (pid + avd arg).
sd=$(sed -n 's/^path=//p' "$HOME/.android/avd/${1:?avd}.ini"); ls -la "$sd"/*.lock 2>&1 | head
ps -axo pid=,command= | grep -E 'qemu-system|emulator ' | grep -v grep | sed -E 's/(-avd [^ ]+).*/\1/' | cut -c1-160
