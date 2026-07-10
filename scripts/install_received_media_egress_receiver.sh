#!/usr/bin/env bash
set -euo pipefail

device_id="${1:?usage: install_received_media_egress_receiver.sh <device-id>}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/integration_test/support/android_received_media_egress_receiver"
"$repo_root/android/gradlew" -p "$project" :app:assembleDebug
adb -s "$device_id" install -r "$project/app/build/outputs/apk/debug/app-debug.apk"
