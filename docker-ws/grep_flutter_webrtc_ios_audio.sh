#!/usr/bin/env bash
# Print how the installed flutter_webrtc iOS plugin touches AVAudioSession /
# RTCAudioSession (manual audio, activation) — read-only, runs on the Mac.
set -u
DIR=$(ls -d "$HOME"/.pub-cache/hosted/pub.dev/flutter_webrtc-1.6.0 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo "NO_PLUGIN_SOURCE"; exit 2; }
echo "plugin: $DIR"
echo "--- AudioUtils.m ---"
sed -n '1,60p' "$DIR/common/darwin/Classes/AudioUtils.m"
echo "--- FlutterRTCMediaStream.m 165-185 (ensureAudioSession caller) ---"
sed -n '165,185p' "$DIR/common/darwin/Classes/FlutterRTCMediaStream.m"
echo "--- manual audio anywhere in plugin? ---"
grep -rn -E 'useManualAudio|isAudioEnabled|audioSessionDidActivate' "$DIR/common" "$DIR/ios" 2>/dev/null | head -5 || true
