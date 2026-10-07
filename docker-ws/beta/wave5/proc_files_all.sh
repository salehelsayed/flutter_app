#!/bin/bash
# Read-only: regular files, pipes and sockets open by a pid.
lsof -p "$1" 2>/dev/null | awk '$5=="REG" || $5=="PIPE" || $5=="unix" || $5=="IPv4" || $5=="IPv6"' | grep -v "\.dylib\|\.so\|dartvm\|snapshot" | cut -c1-200 | tail -15
