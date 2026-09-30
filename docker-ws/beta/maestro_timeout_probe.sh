#!/bin/bash
# Read-only: which startup-timeout env vars does the installed Maestro read?
for j in ~/.maestro/lib/maestro-client*.jar ~/.maestro/lib/maestro-cli*.jar ~/.maestro/lib/maestro-ios*.jar; do
  [ -f "$j" ] || continue
  echo "--- $(basename "$j")"
  unzip -p "$j" 2>/dev/null | strings 2>/dev/null | grep -oE "MAESTRO_[A-Z_]*TIMEOUT[A-Z_]*" | sort -u
done
