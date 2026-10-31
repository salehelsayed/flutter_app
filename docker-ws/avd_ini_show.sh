#!/bin/bash
# Read-only: show the top-level .ini of AVDs.
for a in "$@"; do echo "== $a"; cat "$HOME/.android/avd/$a.ini"; done
