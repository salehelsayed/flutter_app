#!/bin/bash
# Pixel: type a short harmless probe string into the focused field, then report EditText text length.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"; S=21071FDF600CSC
adb -s $S shell "input text '${1:-abc}'"; sleep 1
bash "$(dirname "$0")/store129_pixel_field_probe.sh"
