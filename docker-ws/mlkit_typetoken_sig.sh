#!/bin/bash
# Read-only: for each TypeToken subclass in an APK's dex (TypeToken obfuscated name given), print whether it carries a dalvik Signature annotation.
#   host-run bash docker-ws/mlkit_typetoken_sig.sh <apk-in-repo> <obfuscated TypeToken class, e.g. y73>
cd "$(dirname "$0")/.."
APK="$1"; TT="L$2;"
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
T=$(mktemp -d); unzip -q -o "$APK" 'classes*.dex' -d "$T"
for d in "$T"/classes*.dex; do
  "$BT/dexdump" -d -h "$d" 2>/dev/null | awk -v tt="$TT" '
    /Class descriptor/ {cls=$4; gsub(/\x27/,"",cls)}
    /Superclass/ {sup=$3; gsub(/\x27/,"",sup); if (sup==tt) subs[cls]=1}
  END {for (c in subs) print c}' > "$T/subs.txt"
  [ -s "$T/subs.txt" ] || continue
  "$BT/dexdump" -a "$d" 2>/dev/null > "$T/ann.txt"
  while read -r c; do
    if awk -v c="$c" 'index($0,"Class #")&&f{exit} index($0,c)&&/class/{f=1} f&&/dalvik\/annotation\/Signature/{s=1;exit} END{exit !s}' "$T/ann.txt"; then echo "$c Signature=YES"; else echo "$c Signature=NO"; fi
  done < "$T/subs.txt"
done
rm -rf "$T"
