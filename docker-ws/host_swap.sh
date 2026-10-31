#!/bin/bash
# Read-only: swap usage, CPU count, free memory percent.
sysctl -n vm.swapusage hw.ncpu
memory_pressure 2>/dev/null | tail -1
