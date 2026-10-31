#!/bin/bash
# Read-only audit of audio files on the Pixel that the shell user can see (shared storage, app external dir,
# /data/local/tmp), plus whether run-as works for the Mknoon app. Lists name, size, mtime and sha256; never plays audio.
#   host-run bash docker-ws/pixel_audio_audit.sh <out-dir-in-repo>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$REPO/${1:?out}"; mkdir -p "$OUT"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"; S=21071FDF600CSC
sh() { timeout 60 "$ADB" -s "$S" shell "$@" 2>&1; }
{
  echo "== device time: $(sh date '+%F %T')"
  echo "== run-as com.mknoon.app (release build expected to refuse)"; sh run-as com.mknoon.app id
  for d in /sdcard/Download /sdcard/Music /sdcard/Recordings /sdcard/Android/data/com.mknoon.app /sdcard/Android/media/com.mknoon.app /data/local/tmp; do
    echo "== find in $d"
    sh "find $d -type f \\( -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.amr' -o -iname '*.mp4' -o -iname '*tts*' -o -iname '*voice*' -o -iname '*audio*' \\) -exec ls -l {} \\; 2>/dev/null | head -50"
  done
  echo "== sha256 of found audio files"
  for f in $(sh "find /sdcard/Download /sdcard/Music /sdcard/Android/data/com.mknoon.app /data/local/tmp -type f \\( -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.mp3' -o -iname '*.opus' \\) 2>/dev/null" | tr -d '\r' | head -30); do
    echo "$(sh sha256sum "$f" | tr -d '\r')"
  done
} > "$OUT/pixel_audio_listing.txt"
cat "$OUT/pixel_audio_listing.txt" | cut -c1-200
