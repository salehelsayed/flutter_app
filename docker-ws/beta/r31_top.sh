#!/bin/bash
# Read-only: Mac load and the top CPU users (command lines cut short).
echo "load: $(sysctl -n vm.loadavg)  cpus: $(sysctl -n hw.ncpu)"
ps -axo pcpu,etime,command -r | head -${1:-15} | cut -c1-170
