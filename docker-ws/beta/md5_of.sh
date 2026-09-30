#!/bin/bash
# Print the md5 of files as the Mac sees them (container writes reach the Mac late).
for f in "$@"; do echo "$(md5 -q "$f" 2>/dev/null) $f"; done
