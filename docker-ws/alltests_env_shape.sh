#!/bin/bash
# Read-only: print the run env scripts with every assigned value masked.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
for f in run-env-after-source039.sh run-env-next.sh; do echo "== $f =="; sed -E 's/=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ;]*)/=<masked>/g' "$run/$f"; done
