#!/bin/bash
# Read-only: find virtual-scene environment config option names in emulator binaries.
SDK="$HOME/Library/Android/sdk/emulator"
for f in "$SDK/emulator" "$SDK/qemu/darwin-aarch64/qemu-system-aarch64-headless" "$SDK"/lib64/*.dylib; do
  [ -f "$f" ] || continue
  strings "$f" 2>/dev/null | grep -i -E "environment config|virtualscene|environment_config|envconfig|\.textproto|mesh3d|scene mode|camera-environment|-camera-" | sed "s|^|$(basename "$f"): |" | head -25
done | sort -u | head -80
