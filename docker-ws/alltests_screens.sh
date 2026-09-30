#!/bin/bash
# Screenshots of the Pixel and the iPhone 11 into docker-ws/.run_handover_copy/screens (read-only on devices).
d=/Volumes/CrucialX9/flutter_app/docker-ws/.run_handover_copy/screens; mkdir -p "$d"
adb -s 21071FDF600CSC exec-out screencap -p > "$d/pixel.png" && sips -Z 900 "$d/pixel.png" >/dev/null && echo pixel-ok
adb -s 21071FDF600CSC shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | head -2
