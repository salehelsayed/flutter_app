#!/bin/bash
# Tap play on the newest voice-message bubble on the emulator and show the bubble state.
. "$(dirname "$0")/emu.sh"
b=$(grep -oE '<node [^>]*Voice message[^>]*>' "$EOUT/e_v2.xml" | tail -1 | grep -oE 'bounds="[^"]*"'); echo "$b"
set -- $(echo "$b" | grep -oE '[0-9]+')
eadb shell input tap $(( $1 + 90 )) $(( ($2 + $4) / 2 )); sleep 2
e_dump v3 | tr '"' '\n' | grep -iE 'voice|pause|play|0:0' | head -4
e_shot alice_voice_play
