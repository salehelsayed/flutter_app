#!/bin/bash
# Retry: add the photos to the iPhone, record a real video (errors shown), push it to both.
. "$(dirname "$0")/beta_env.sh"
M=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260927/media
: photos already added
V=$(mktemp -d /tmp/r2vid.XXXX); chmod 777 "$V"
( xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$V/r2_video_1.mov" > "$M/record.log" 2>&1 ) &
sleep 7
pkill -INT -f "simctl io $UDID recordVideo"
sleep 3
cat "$M/record.log" | tail -5
cp "$V/r2_video_1.mov" "$M/" 2>/dev/null; ls -la "$M"
if [ -s "$M/r2_video_1.mov" ]; then
  # H.264 .mov -> .mp4 container for Android's gallery
  avconvert --source "$M/r2_video_1.mov" --preset PresetPassthrough --output "$M/r2_video_1.mp4" --replace > /dev/null 2>&1 \
    || cp "$M/r2_video_1.mov" "$M/r2_video_1.mp4"
  ls -la "$M/r2_video_1.mp4"
  $ADB push "$M/r2_video_1.mp4" /sdcard/Movies/ > /dev/null 2>&1
  $ADB shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Movies/r2_video_1.mp4 > /dev/null 2>&1
  sleep 3
  echo "android videos: $($ADB shell content query --uri content://media/external/video/media --projection _display_name 2>&1 | grep -c r2_video)"
  xcrun simctl addmedia "$UDID" "$M/r2_video_1.mp4" 2>&1 | tail -2; echo "ios video rc=${PIPESTATUS[0]}"
fi
echo "MEDIA FIX DONE"
