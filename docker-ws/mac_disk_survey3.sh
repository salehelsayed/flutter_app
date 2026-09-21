#!/bin/bash
set -uo pipefail
hr() { echo; echo "=== $* ==="; }
g() { awk '{ if ($1 ~ /^[0-9]+$/) { printf "%8.2f GB  ", $1/1048576; $1=""; print } else print }'; }

hr "df now"
df -h / /System/Volumes/Data /Volumes/CrucialX9

hr "purgeable / diskutil info Data"
diskutil info /System/Volumes/Data 2>/dev/null | grep -iE "purge|free|used|capacity|snapshot"

hr "Data volume top level (depth 1)"
du -kx -d 1 /System/Volumes/Data 2>/dev/null | sort -rn | head -20 | g

hr "OneDrive: on-disk vs logical"
OD="$HOME/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite"
du -skx "$OD" 2>/dev/null | g
echo "-- logical bytes of all files under OneDrive --"
find "$OD" -type f -print0 2>/dev/null | xargs -0 -n 200 stat -f '%z %b' 2>/dev/null \
  | awk '{log+=$1; blk+=$2*512} END {printf "logical %.2f GB   allocated %.2f GB   files %d\n", log/1073741824, blk/1073741824, NR}'
echo "-- dataless (cloud-only) placeholder count --"
find "$OD" -type f -size -1 2>/dev/null | wc -l

hr "Docker Desktop disk image location"
cat "$HOME/Library/Group Containers/group.com.docker/settings-store.json" 2>/dev/null | tr ',' '\n' | grep -iE "diskPath|dataFolder|DiskSizeMiB" 
cat "$HOME/Library/Group Containers/group.com.docker/settings.json" 2>/dev/null | tr ',' '\n' | grep -iE "diskPath|dataFolder|DiskSizeMiB"
echo "-- search for Docker.raw / docker VM disks anywhere --"
ls -lh "$HOME/Library/Containers/com.docker.docker/Data/vms/0/" 2>/dev/null
find /Volumes/CrucialX9 -maxdepth 4 -name "Docker.raw" -o -maxdepth 4 -name "docker.raw" 2>/dev/null | head -5
du -skx "/Volumes/CrucialX9/DockerData" 2>/dev/null | g

hr "top 25 biggest dirs on Data volume, depth 3, excluding OneDrive"
du -kx -d 3 /System/Volumes/Data 2>/dev/null | sort -rn | head -40 | g

hr "sleepimage / swap"
ls -lh /private/var/vm/ 2>/dev/null

hr "done3"
