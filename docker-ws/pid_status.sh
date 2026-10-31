#!/bin/bash
# Read-only: is exact pid alive, and its command (first 160 chars) and children.
p=${1:?pid}; ps -o pid=,ppid=,etime=,command= -p "$p" 2>/dev/null | cut -c1-200 || true; echo children:; pgrep -P "$p" 2>/dev/null | while read c; do ps -o pid=,command= -p "$c" | cut -c1-160; done
