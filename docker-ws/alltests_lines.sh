#!/bin/bash
# Read-only: print line range of a run-root text file, cut. Usage: <relpath> <from> <to> [width]
f="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1"; case "$1" in (*run-env*|*private*) exit 2;; esac
sed -n "$2,$3p" "$f" | cut -c1-${4:-260}
