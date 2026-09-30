#!/bin/bash
P=$(ps -axo pid,command | grep qemu-system | grep -- '-port 5556' | grep -v grep | awk '{print $1}' | head -1)
ps -M -p "$P" | head -6; ps -M -p "$P" | wc -l
