#!/bin/bash
# Read-only: exact free KB on the external drive.
df -k /Volumes/CrucialX9 | awk 'NR==2{printf "free_kb=%d free_GB_decimal=%.2f\n", $4, $4*1024/1e9}'
