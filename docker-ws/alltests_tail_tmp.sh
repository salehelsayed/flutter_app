#!/bin/bash
# Read-only: size/mtime and last lines of an all-tests tmp output file.
f="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp/$1"
date; ls -la "$f"; echo "lines: $(wc -l < "$f")"; tail -c "${2:-6000}" "$f" | sed -E 's/(token|password|secret)[^ ]*/\1=REDACTED/Ig'
