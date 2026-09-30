#!/bin/bash
# Read-only: how macOS sees the emulator-5556 qemu process (LaunchServices app info, power assertions, App Nap setting).
P=$(ps -axo pid,command | grep qemu-system | grep -- '-port 5556' | grep -v grep | awk '{print $1}' | head -1)
O=$(ps -axo pid,command | grep qemu-system | grep -v -- '-port 5556' | grep -v grep | awk '{print $1}' | head -1)
echo "5556 pid=$P  other pid=$O"
echo "--- lsappinfo (5556)"; lsappinfo info -only name,bundleid,applicationtype,pid,parentasn,isvisible,isforeground,appnap "$(lsappinfo find pid=$P 2>/dev/null)" 2>&1 | head -12
lsappinfo list 2>/dev/null | grep -B2 -A14 "pid = $P" | grep -iE 'qemu|bundle|type|nap|visible|hidden|front|LSBackground|pid =' | head -14
echo "--- lsappinfo (other)"; lsappinfo list 2>/dev/null | grep -B2 -A14 "pid = $O" | grep -iE 'qemu|bundle|type|nap|visible|hidden|front|pid =' | head -8
echo "--- assertions held by qemu"; pmset -g assertions 2>/dev/null | grep -iE 'qemu|emulator' | head
echo "--- App Nap global setting: $(defaults read NSGlobalDomain NSAppSleepDisabled 2>&1)"
echo "--- priorities now: 5556 $(ps -o pri=,%cpu= -p $P | tr -s ' ') other $(ps -o pri=,%cpu= -p $O | tr -s ' ')"
echo "--- parent of 5556: $(ps -o ppid= -p $P | tr -d ' ') -> $(ps -o command= -p $(ps -o ppid= -p $P | tr -d ' ') | cut -c1-120)"
echo "--- parent of other: $(ps -o ppid= -p $O | tr -d ' ') -> $(ps -o command= -p $(ps -o ppid= -p $O | tr -d ' ') | cut -c1-120)"
