#!/bin/bash
# Read-only: grep a run-root log for error lines. Usage: <relpath> [pattern]
f="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1"; case "$1" in (*run-env*|*private*) exit 2;; esac
grep -nE "${2:-error:}" "$f" | cut -c1-400 | head -25
