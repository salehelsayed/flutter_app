#!/bin/bash
# Read-only: exact byte size of the Gemma model inside the Mknoon container on the iPhone 11 (devicectl JSON output).
U=00008030-001A6D2801BB802E; J=/tmp/gemma_files_$$.json
timeout 120 xcrun devicectl device info files --device $U --domain-type appDataContainer --domain-identifier com.mknoon.app \
  --subdirectory Documents --json-output "$J" >/dev/null 2>&1; echo "exit=$?"
grep -o -E '"(fileSize|size|byteCount|totalSize)"[^,}]{0,30}' "$J" | head -5
grep -o -E 'gemma[^"]{0,40}' "$J" | head -2
rm -f "$J"
