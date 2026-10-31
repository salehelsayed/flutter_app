#!/bin/bash
# Read-only: count mprotect errors in past headless emulator logs (names only).
for f in /tmp/emulator_*.log; do printf '%s mprotect=%s boot_ok=%s\n' "$(basename "$f")" "$(grep -c 'mprotect failed' "$f")" "$(grep -c -i 'boot completed\|Boot completed' "$f")"; done | tail -12
