#!/bin/bash
# Read-only disk usage for the external drive.
df -h /Volumes/CrucialX9
df -k /Volumes/CrucialX9 | awk 'NR==2{print "free_gb=" int($4/1048576) " used_gb=" int($3/1048576)}'
