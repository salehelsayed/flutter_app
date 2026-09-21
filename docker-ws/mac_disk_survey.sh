#!/bin/bash
# Read-only survey of what is using space on the Mac's internal disk.
# Run: /claude-host-bin/host-run bash docker-ws/mac_disk_survey.sh
set -uo pipefail

hr() { echo; echo "=== $* ==="; }

hr "date / host"
date
sw_vers 2>/dev/null

hr "df -h (all volumes)"
df -h

hr "APFS container space (purgeable / snapshots)"
diskutil apfs list 2>/dev/null | sed -n '1,120p'

hr "Time Machine local snapshots on /"
tmutil listlocalsnapshots / 2>&1 | head -40

hr "system_profiler storage"
system_profiler SPStorageDataType 2>/dev/null | head -60

hr "top-level of / (internal volume only, depth 1)"
du -kx -d 1 / 2>/dev/null | sort -rn | head -25

hr "home dir, depth 2 (top 45)"
du -kx -d 2 "$HOME" 2>/dev/null | sort -rn | head -45

hr "known dev-tool space hogs"
for p in \
  "$HOME/Library/Containers/com.docker.docker/Data" \
  "$HOME/Library/Group Containers/group.com.docker" \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
  "$HOME/Library/Developer/Xcode/watchOS DeviceSupport" \
  "$HOME/Library/Developer/Xcode/Archives" \
  "$HOME/Library/Developer/Xcode/Products" \
  "$HOME/Library/Developer/CoreSimulator/Devices" \
  "$HOME/Library/Developer/CoreSimulator/Caches" \
  "$HOME/Library/Developer/CoreDevice" \
  "$HOME/Library/Caches" \
  "$HOME/Library/Caches/Homebrew" \
  "$HOME/Library/Caches/CocoaPods" \
  "$HOME/Library/Caches/com.apple.dt.Xcode" \
  "$HOME/Library/Application Support/MobileSync/Backup" \
  "$HOME/Library/Logs" \
  "$HOME/.pub-cache" \
  "$HOME/.gradle" \
  "$HOME/.cocoapods" \
  "$HOME/.android" \
  "$HOME/.npm" \
  "$HOME/.cache" \
  "$HOME/go/pkg/mod" \
  "$HOME/Library/Android/sdk" \
  "$HOME/Downloads" \
  "$HOME/Desktop" \
  "$HOME/Documents" \
  "$HOME/Movies" \
  "$HOME/Pictures" \
  "$HOME/.Trash" \
  "/Library/Developer/CoreSimulator/Profiles/Runtimes" \
  "/Library/Developer/CoreSimulator/Volumes" \
  "/Applications" \
  "/Library/Caches" \
  "/opt/homebrew" \
  "/usr/local" \
  "/private/var/vm" \
  "/private/var/folders" \
  "/Library/Logs/DiagnosticReports" ; do
  if [ -e "$p" ]; then
    sz=$(du -skx "$p" 2>/dev/null | awk '{print $1}')
    [ -n "${sz:-}" ] && printf '%10d KB  %s\n' "$sz" "$p"
  fi
done | sort -rn

hr "Xcode DerivedData entries"
du -kx -d 1 "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | sort -rn | head -20

hr "iOS DeviceSupport entries (one per iOS build ever attached)"
du -kx -d 1 "$HOME/Library/Developer/Xcode/iOS DeviceSupport" 2>/dev/null | sort -rn | head -30

hr "Simulator runtimes installed"
du -kx -d 1 "/Library/Developer/CoreSimulator/Profiles/Runtimes" 2>/dev/null | sort -rn | head -20
ls -1 /Library/Developer/CoreSimulator/Volumes 2>/dev/null

hr "Simulator devices (xcrun simctl)"
xcrun simctl list devices 2>/dev/null | head -60

hr "files over 1 GB on the internal volume under /Users, /Applications, /Library, /opt, /usr/local"
find /Users /Applications /Library /opt /usr/local -xdev -type f -size +1g 2>/dev/null -exec ls -l {} \; | awk '{printf "%10.2f GB  ", $5/1073741824; for(i=9;i<=NF;i++) printf "%s ", $i; print ""}' | sort -rn | head -40

hr "docker disk usage (if daemon reachable)"
docker system df 2>&1 | head -20

hr "done"
