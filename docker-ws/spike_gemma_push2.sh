#!/bin/bash
# Push the owner's Gemma model to /data/local/tmp (adb push verifies the transfer), copy it into the spike app's private files, check size+sha, delete the staging copy.
P=21071FDF600CSC; F=/Volumes/CrucialX9/flutter_app/gemma-ai/gemma-3n-E2B-it-int4.litertlm; T=/data/local/tmp/gemma-e2b.litertlm
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s $P shell run-as com.mknoon.translatespike rm -f files/gemma-3n-E2B-it-int4.litertlm
echo "push start $(date -u +%T)"; adb -s $P push "$F" $T 2>&1 | tail -1; adb -s $P shell chmod 644 $T
adb -s $P shell run-as com.mknoon.translatespike mkdir -p files
adb -s $P shell run-as com.mknoon.translatespike cp $T files/gemma-3n-E2B-it-int4.litertlm; echo "cp exit=$?"
adb -s $P shell rm -f $T
adb -s $P shell run-as com.mknoon.translatespike ls -l files/gemma-3n-E2B-it-int4.litertlm
adb -s $P shell run-as com.mknoon.translatespike sha256sum files/gemma-3n-E2B-it-int4.litertlm
echo "done $(date -u +%T)"
