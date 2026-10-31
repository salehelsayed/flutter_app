#!/bin/bash
# Read-only: count dalvik Signature annotations that mention a class prefix (e.g. "Ly73<") across an APK's dex files.
#   host-run bash docker-ws/mlkit_sig_count.sh <apk-in-repo> <obfuscated class name>
cd "$(dirname "$0")/.."
export LC_ALL=C
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
T=$(mktemp -d); unzip -q -o "$1" 'classes*.dex' -d "$T"
n=0; s=0
for d in "$T"/classes*.dex; do
  "$BT/dexdump" -a "$d" 2>/dev/null > "$T/a.txt"
  a=$(grep -a -c "L$2<" "$T/a.txt"); b=$(grep -a -c "dalvik/annotation/Signature" "$T/a.txt"); n=$((n+a)); s=$((s+b))
done
echo "mentions L$2< = $n   total Signature annotations = $s"
rm -rf "$T"
