#!/bin/bash
# Read-only: cpu/state of a pid twice, 5 s apart, and its most recently opened regular files.
ps -o pid=,%cpu=,time=,state= -p "$1"; sleep 5; ps -o pid=,%cpu=,time=,state= -p "$1"
lsof -p "$1" 2>/dev/null | awk '$5=="REG"' | tail -5 | awk '{print $NF}' | cut -c1-150
