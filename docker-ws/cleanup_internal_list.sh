#!/bin/bash
# Read-only: internal-disk cleanup candidates (sizes, ages): Xcode DerivedData Runner-*, CoreSimulator logs, DiagnosticReports,
# Xcode Archives, large files in /tmp and $TMPDIR. Deletes nothing.
#   host-run bash docker-ws/cleanup_internal_list.sh
echo "== disk"; df -h / | awk 'NR==2{print $4" free of "$2}'
echo "== Xcode DerivedData"; for d in "$HOME"/Library/Developer/Xcode/DerivedData/*; do [ -d "$d" ] && echo "$(du -sh "$d" 2>/dev/null | cut -f1) $(stat -f %Sm -t %m-%dT%H:%M "$d") $(basename "$d")"; done
echo "== CoreSimulator logs"; du -sh "$HOME/Library/Logs/CoreSimulator" 2>/dev/null
echo "== DiagnosticReports"; du -sh "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null
echo "== Xcode Archives"; for d in "$HOME"/Library/Developer/Xcode/Archives/*; do [ -d "$d" ] && echo "$(du -sh "$d" 2>/dev/null | cut -f1) $(basename "$d")"; done
echo "== big files in /tmp and TMPDIR (>50M)"; find /tmp "${TMPDIR:-/tmp}" -maxdepth 3 -type f -size +50M 2>/dev/null | while read f; do echo "$(du -sh "$f" | cut -f1) $(stat -f %Su "$f") $f"; done | head -20
echo "== big dirs in /tmp and TMPDIR (>200M)"; for d in /tmp/* "${TMPDIR:-/tmp}"/*; do [ -d "$d" ] || continue; s=$(du -sm "$d" 2>/dev/null | cut -f1); [ "${s:-0}" -gt 200 ] && echo "${s}MB $(stat -f %Su "$d") $d"; done | head -20
