#!/bin/bash
# Stop one emulator by serial with the console kill command (no pattern kills).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S="${1:?serial}"; case "$S" in emulator-*) ;; *) exit 2;; esac
adb -s "$S" emu kill; sleep 8; adb devices; ps -p "${2:-0}" >/dev/null 2>&1 && echo "pid $2 still alive" || echo "pid ${2:-?} gone"
