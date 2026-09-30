#!/bin/bash
# Read-only: tail a non-private text file under the run root (masking token-like values). Usage: <relpath> [bytes]
f="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1"
case "$1" in (*run-env*|*private*) echo REFUSED; exit 2;; esac
tail -c "${2:-6000}" "$f" | sed -E 's/((token|key|secret|password)[A-Za-z_]*[=:] *)[^ ,"]+/\1<masked>/Ig'
