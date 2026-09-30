#!/bin/bash
# Read-only: just_audio source around the line in the stack trace (pub cache on the Mac).
V=$(awk '/^  just_audio:/{f=1} f&&/version:/{gsub(/"/,"",$2); print $2; exit}' /Volumes/CrucialX9/flutter_app/pubspec.lock)
F=~/.pub-cache/hosted/pub.dev/just_audio-$V/lib/just_audio.dart
echo "just_audio $V"; sed -n '1380,1410p' "$F"
echo "--- dispose()"; grep -n "Future<void> dispose()" -A28 "$F" | head -40
