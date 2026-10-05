#!/bin/bash
# Read-only: newest Maestro test-log folders with birth time.
ls -dt ~/.maestro/tests/*/ 2>/dev/null | head -8 | while read d; do echo "$(stat -f '%SB' -t '%H:%M:%S' "$d") $d $(ls "$d" | tr '\n' ' ' | cut -c1-80)"; done
