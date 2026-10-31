#!/bin/bash
# Read-only: strings around the imagefile camera mode in the headless qemu binary.
Q="$HOME/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64-headless"
strings "$Q" | grep -n -i -E "imagefile|videofile|image360|image_file|file=|path=|loop=" | head -40
