#!/bin/bash
# Stream the owner's Gemma E2B model into the spike app's private storage on the Pixel (source file is only read), then verify size.
P=21071FDF600CSC; F=/Volumes/CrucialX9/flutter_app/gemma-ai/gemma-3n-E2B-it-int4.litertlm
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s $P shell df -k /data | tail -1
adb -s $P shell run-as com.mknoon.translatespike mkdir -p files
echo "push start $(date -u +%T)"
adb -s $P exec-in run-as com.mknoon.translatespike dd of=files/gemma-3n-E2B-it-int4.litertlm bs=1048576 < "$F"; echo "dd exit=$?"
echo "push end $(date -u +%T)"
adb -s $P shell run-as com.mknoon.translatespike ls -l files/gemma-3n-E2B-it-int4.litertlm
