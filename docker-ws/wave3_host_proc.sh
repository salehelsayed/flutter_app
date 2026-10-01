#!/bin/bash
# Prints the full command line of one Mac process and of its parent.
p=$1; ps -o pid,ppid,etime,command -p "$p" | cat; pp=$(ps -o ppid= -p "$p"); ps -o pid,ppid,etime,command -p $pp | cat
for d in 21071FDF600CSC emulator-5554 emulator-5556 emulator-5560; do printf '%s ' "$d"; printf '%s' "$d" | shasum -a 256 | cut -c1-16; done
