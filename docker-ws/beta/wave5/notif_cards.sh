#!/bin/bash
# Read-only: Mknoon packages with posted notifications on the Pixel and emulator-5554.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for s in 21071FDF600CSC emulator-5554; do
  echo "== $s"; adb -s $s shell dumpsys notification --noredact 2>/dev/null | grep -oE "pkg=com\.mknoon[a-z.]*" | sort | uniq -c
done
