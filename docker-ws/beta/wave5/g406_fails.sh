#!/bin/bash
# Plan 406: list failing tests in the host-all log, read on the Mac.
L=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406_hostall.log
grep -aE "\[E\]$" "$L" | sed -E 's/^\+[0-9]+ (~[0-9]+ )?-[0-9]+: //' | sort -u | head -20
