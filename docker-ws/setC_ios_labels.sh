#!/bin/bash
# Print the unique accessibility labels of the current iPhone 13 Mknoon screen (Appium page source text only, never a screenshot).
cd "$(dirname "$0")/.." && timeout 120 python3 docker-ws/beta/ap.py 13 src | grep -oE 'label="[^"]{1,200}"' | awk '!s[$0]++'
