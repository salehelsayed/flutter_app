#!/bin/bash
# Read-only: recent port/bind errors in another worktree test logs.  host-run bash docker-ws/find_port_errors.sh <worktree>
W="${1:?}"; case "$W" in /Volumes/CrucialX9/flutter_app_*) ;; *) echo refused; exit 2;; esac
P="address already in use|EADDRINUSE|bind failed|no free port|port.*(exhaust|unavailable)|netsim"
find "$W/.codex-test-logs" -type f -mmin -240 \( -name "*.log" -o -name "*.txt" -o -name "*.json" \) 2>/dev/null | head -4000 | xargs grep -l -i -E "$P" 2>/dev/null | head -10 | while read f; do echo "== $f"; grep -i -m3 -E "$P" "$f" | cut -c1-300; done
