#!/bin/bash
# Read-only: running `maestro test` processes with start time and target device.
ps -axo pid=,etime=,command= | grep "maestro.cli.AppKt test" | grep -v grep | sed -E 's/.*(--device [^ ]+).*/\0/' | awk '{print $1, $2}' 
for p in $(pgrep -f "maestro.cli.AppKt test"); do echo "$p $(ps -o command= -p $p | grep -o -- '--device [^ ]*')"; done
