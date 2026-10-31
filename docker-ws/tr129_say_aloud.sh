#!/bin/bash
# Build-129 translation test: after <delay> s, play a short German TTS sentence aloud on the Mac speaker
# so a phone recording a voice note next to the Mac picks it up. Prints the volume it used.
#   host-run bash docker-ws/tr129_say_aloud.sh <delay-secs>
sleep "${1:-3}"
echo "output volume: $(osascript -e 'output volume of (get volume settings)') muted: $(osascript -e 'output muted of (get volume settings)')"
say -v Anna -r 140 "Guten Abend. Ich komme morgen um zehn Uhr zum Bahnhof und bringe zwei Bücher mit."
echo "played at $(date -u +%T)"
