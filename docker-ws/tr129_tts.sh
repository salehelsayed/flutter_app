#!/bin/bash
# Build-129 translation test: make a short German TTS clip on the Mac (no playback).
#   host-run bash docker-ws/tr129_tts.sh <out.m4a-in-repo>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; mkdir -p "$(dirname "$O")"
say -v Anna -r 150 -o "$O" --file-format=m4af --data-format=aac "Guten Abend. Ich komme morgen um zehn Uhr zum Bahnhof und bringe zwei Bücher mit." && ls -l "$O"
