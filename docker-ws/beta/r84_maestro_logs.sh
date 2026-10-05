#!/bin/bash
# Read-only: Maestro's own test logs started between two local times (HH:MM), driver-start lines only.
for d in $(ls -dt ~/.maestro/tests/*/ 2>/dev/null | head -40); do
  t=$(stat -f '%SB' -t '%H:%M' "$d")
  if [[ "$t" > "$1" && "$t" < "$2" ]]; then
    echo "== $d ($t)"
    grep -h -i -E "xctest|xcodebuild|runner|port|driver|install|error|fail" "$d"/maestro.log 2>/dev/null \
      | grep -v -E "^\s+at " | head -${3:-25} | cut -c1-230
  fi
done
