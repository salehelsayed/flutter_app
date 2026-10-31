#!/bin/bash
# Read-only: diff the config.ini of two AVDs (sorted keys).
p() { d=$(sed -n 's/^path=//p' "$HOME/.android/avd/$1.ini"); sort "$d/config.ini"; }
diff <(p "$1") <(p "$2")
