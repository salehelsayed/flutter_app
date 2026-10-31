#!/bin/bash
# Read-only: list local provisioning profiles for com.mknoon.app (type, expiry, increased-memory-limit entitlement),
# and the entitlements of a built Runner.app.   host-run bash docker-ws/translate_main_profile_probe.sh [Runner.app path]
for d in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  [ -d "$d" ] || continue
  for p in "$d"/*.mobileprovision "$d"/*.provisionprofile; do
    [ -f "$p" ] || continue
    x=$(security cms -D -i "$p" 2>/dev/null) || continue
    echo "$x" | grep -q 'com\.mknoon\.app<' || continue
    t=$(mktemp); echo "$x" > "$t"
    name=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$t" 2>/dev/null)
    appid=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$t" 2>/dev/null)
    exp=$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$t" 2>/dev/null)
    created=$(/usr/libexec/PlistBuddy -c 'Print :CreationDate' "$t" 2>/dev/null)
    gta=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$t" 2>/dev/null)
    devs=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$t" 2>/dev/null | grep -c '[0-9a-f]\{8\}')
    mem=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.kernel.increased-memory-limit' "$t" 2>/dev/null || echo absent)
    echo "PROFILE file=$(basename "$p") name='$name' appid=$appid get-task-allow=$gta devices=$devs created='$created' expires='$exp' increased-memory-limit=$mem"
    rm -f "$t"
  done
done
if [ -n "${1:-}" ] && [ -d "$1" ]; then
  echo "== app $1"; codesign -d --entitlements :- "$1" 2>/dev/null | grep -A1 -E 'increased-memory|aps-environment|get-task-allow' | tr -d '\t'
  security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | grep -A1 -E '<key>Name<|increased-memory' | tr -d '\t'
fi
