#!/bin/bash
# Read-only: show emulator help lines about camera / virtual scene posters.
"$HOME/Library/Android/sdk/emulator/emulator" -help 2>&1 | grep -i -A1 "camera\|virtualscene\|poster"
