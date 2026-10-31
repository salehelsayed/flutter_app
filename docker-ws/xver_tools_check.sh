#!/bin/bash
# Read-only: tool availability and running emulators for the chat-open bisect.
for t in ffmpeg ffprobe; do printf "%s=%s\n" $t "$(command -v $t || ls /opt/homebrew/bin/$t 2>/dev/null || echo missing)"; done
"$HOME/Library/Android/sdk/emulator/emulator" -list-avds
adb devices | tail -n +2
