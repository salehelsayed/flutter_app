#!/bin/bash
# Read-only: load average, swap and free memory on the Mac.
sysctl -n vm.loadavg; sysctl vm.swapusage; vm_stat | awk "/Pages free|Pages inactive|Pages speculative/{gsub(\"\\.\",\"\",\$NF); s+=\$NF} END{printf \"free_or_inactive_GB=%.1f\\n\", s*16384/1073741824}"
