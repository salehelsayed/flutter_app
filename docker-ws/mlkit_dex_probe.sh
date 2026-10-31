#!/bin/bash
# Read-only: show dexdump annotation lines near a class descriptor in an APK.
#   host-run bash docker-ws/mlkit_dex_probe.sh <apk-in-repo> <class descriptor, e.g. Lpu0;>
cd "$(dirname "$0")/.."
export LC_ALL=C
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
T=$(mktemp -d); unzip -q -o "$1" 'classes*.dex' -d "$T"
for d in "$T"/classes*.dex; do
  "$BT/dexdump" -a "$d" 2>/dev/null | grep -a -n -E "Class descriptor  : '$2'|Superclass .*'$2'" | head -3 | sed "s|^|$(basename "$d"): |"
done
d=$(for d in "$T"/classes*.dex; do "$BT/dexdump" -a "$d" 2>/dev/null | grep -a -q "Class descriptor  : '$2'" && echo "$d"; done | head -1)
[ -n "$d" ] && "$BT/dexdump" -a "$d" 2>/dev/null | grep -a -n -B12 -A4 "Class descriptor  : '$2'" | cut -c1-200
rm -rf "$T"
