#!/bin/bash
# Phase 2 drill-down. Read-only.
set -uo pipefail
hr() { echo; echo "=== $* ==="; }
g() { awk '{ if ($1 ~ /^[0-9]+$/) { printf "%8.2f GB  ", $1/1048576; $1=""; print } else print }'; }

hr "/Users depth 1"
du -kx -d 1 /Users 2>/dev/null | sort -rn | head -12 | g

hr "/Applications depth 1 (top 25)"
du -kx -d 1 /Applications 2>/dev/null | sort -rn | head -25 | g

hr "~/Library depth 1 (top 20)"
du -kx -d 1 "$HOME/Library" 2>/dev/null | sort -rn | head -20 | g

hr "~/Library/Containers (top 15)"
du -kx -d 1 "$HOME/Library/Containers" 2>/dev/null | sort -rn | head -15 | g

hr "~/Library/Group Containers (top 15)"
du -kx -d 1 "$HOME/Library/Group Containers" 2>/dev/null | sort -rn | head -15 | g

hr "~/Library/Application Support (top 20)"
du -kx -d 1 "$HOME/Library/Application Support" 2>/dev/null | sort -rn | head -20 | g

hr "~/Library/Developer depth 2 (top 20)"
du -kx -d 2 "$HOME/Library/Developer" 2>/dev/null | sort -rn | head -20 | g

hr "~/Library/Caches (top 15)"
du -kx -d 1 "$HOME/Library/Caches" 2>/dev/null | sort -rn | head -15 | g

hr "CoreSimulator devices (top 15)"
du -kx -d 1 "$HOME/Library/Developer/CoreSimulator/Devices" 2>/dev/null | sort -rn | head -15 | g

hr "simctl devices"
/usr/bin/xcrun simctl list devices available 2>&1 | head -50

hr "~/.android/avd"
du -kx -d 1 "$HOME/.android/avd" 2>/dev/null | sort -rn | head -15 | g

hr "~/.codex depth 2"
du -kx -d 2 "$HOME/.codex" 2>/dev/null | sort -rn | head -20 | g
echo "-- oldest/newest session dirs --"
ls -1 "$HOME/.codex/sessions" 2>/dev/null | head -5
ls -1 "$HOME/.codex/sessions" 2>/dev/null | tail -5

hr "~/.hermes depth 2"
du -kx -d 2 "$HOME/.hermes" 2>/dev/null | sort -rn | head -15 | g

hr "~/.claude-docker-home depth 2"
du -kx -d 2 "$HOME/.claude-docker-home" 2>/dev/null | sort -rn | head -15 | g

hr "~/Documents depth 2 (top 20)"
du -kx -d 2 "$HOME/Documents" 2>/dev/null | sort -rn | head -20 | g

hr "~/development depth 1"
du -kx -d 1 "$HOME/development" 2>/dev/null | sort -rn | head -15 | g

hr "~ depth 1 remainder (top 30)"
du -kx -d 1 "$HOME" 2>/dev/null | sort -rn | head -30 | g

hr "docker / orbstack data roots"
for p in "$HOME/.docker" "$HOME/.orbstack" "$HOME/.colima" "$HOME/.lima" "$HOME/Library/Containers/com.docker.docker" "$HOME/Library/Group Containers/group.com.docker"; do
  [ -e "$p" ] && du -skx "$p" 2>/dev/null | g
done
docker context ls 2>&1 | head -10
docker info --format '{{.DockerRootDir}} {{.Driver}} {{.OperatingSystem}}' 2>&1 | head -3

hr "files over 1 GB (internal volume)"
find /Users /Applications /Library /opt /usr/local /private -xdev -type f -size +1G 2>/dev/null -print0 \
  | xargs -0 -n 50 stat -f '%z %N' 2>/dev/null \
  | sort -rn | head -40 \
  | awk '{ printf "%8.2f GB  ", $1/1073741824; $1=""; print }'

hr "purgeable / snapshot totals"
tmutil listlocalsnapshots / 2>&1 | head -20
df -H / /System/Volumes/Data

hr "done2"
