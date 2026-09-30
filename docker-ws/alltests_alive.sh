#!/bin/bash
# Prints ALIVE or EXITED for a launched checkpoint label.
pid=$(cat "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1.launch.pid" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo ALIVE; else echo EXITED; fi
