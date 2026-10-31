#!/bin/bash
# Read-only: is Mknoon running on the iPhone 11, and any Runner crash reports since a given time.
#   host-run bash docker-ws/ios11_mknoon_health.sh <out-file> [since-iso]
U=00008030-001A6D2801BB802E; O="$1"
{ echo "== processes $(date -u +%TZ)"
  timeout 90 /usr/bin/xcrun devicectl device info processes --device "$U" 2>&1 | grep -E 'Runner.app/Runner' | sed -E 's#/private/var/containers/Bundle/Application/[^/]+/#<app>/#' | head -3
  echo "== crash files"
  timeout 120 /usr/bin/xcrun devicectl device info files --device "$U" --domain-type systemCrashLogs 2>&1 | grep -iE 'Runner|mknoon' | tail -10
  echo "== syslog 25s"
  if command -v idevicesyslog >/dev/null; then
    timeout 25 idevicesyslog -u "$U" -p Runner 2>/dev/null | grep -iE 'crash|terminat|exception|jetsam|fatal' | cut -c1-200 | head -10
  else echo "no idevicesyslog"; fi
  echo "== end $(date -u +%TZ)"; } > "$O" 2>&1
