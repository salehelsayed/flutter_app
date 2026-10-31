#!/bin/bash
# Disposable emulator only: remove com.mknoon.app (stale install with a leftover card blocks the receiver precheck).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
S="${1:?emulator serial}"; case "$S" in emulator-*) ;; *) echo "refused: emulators only"; exit 2;; esac
adb -s "$S" uninstall com.mknoon.app; adb -s "$S" shell pm list packages com.mknoon.app | tr -d '\r'
