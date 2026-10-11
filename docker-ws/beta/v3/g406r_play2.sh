#!/bin/bash
. "$(dirname "$0")/emu.sh"
eadb shell input tap 128 1055; sleep 3; e_shot alice_voice_play2
eadb logcat -d -t 400 | grep -iE 'audioplayer|MediaPlayer|ExoPlayer|AudioTrack|voice.*play|PLAYBACK' | tail -6 | cut -c1-200
