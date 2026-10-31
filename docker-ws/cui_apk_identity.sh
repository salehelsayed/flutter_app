#!/bin/bash
# Read-only: package id, version and Firebase project id of an APK (no keys printed).
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | sort -V | tail -1)
"$BT/aapt2" dump badging "$1" 2>/dev/null | head -1 | grep -oE "package: name='[^']*'|versionName='[^']*'"
"$BT/aapt2" dump resources "$1" 2>/dev/null | grep -A1 -E 'string/(project_id|gcm_defaultSenderId)' | grep -oE '"[a-z0-9-]+"' | head -2
unzip -l "$1" 2>/dev/null | grep -oE 'lib/[a-z0-9_-]+/libgojni.so' | sort -u
