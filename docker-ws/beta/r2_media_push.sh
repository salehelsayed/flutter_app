#!/bin/bash
# Put the round 2 test photos and video on both phones (Pixel gallery + iPhone Photos).
. "$(dirname "$0")/beta_env.sh"
M=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260927/media
for i in $(seq 1 60); do [ -f "$M/r2_photo_4.png" ] && break; sleep 2; done   # container writes reach the Mac late
# A real 6 s H.264 video: record the simulator screen (the repo fixtures are tiny stubs).
rm -f "$M/r2_video_1.mp4"
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$M/r2_video_1.mp4" > /dev/null 2>&1 &
RV=$!; sleep 6; kill -INT $RV; wait $RV 2>/dev/null
ls -la "$M"
echo "=== android push"
for f in r2_photo_1.png r2_photo_2.png r2_photo_3.png r2_photo_4.png; do $ADB push "$M/$f" /sdcard/Pictures/ >/dev/null 2>&1; done
$ADB push "$M/r2_video_1.mp4" /sdcard/Movies/ >/dev/null 2>&1
for f in /sdcard/Pictures/r2_photo_1.png /sdcard/Pictures/r2_photo_2.png /sdcard/Pictures/r2_photo_3.png /sdcard/Pictures/r2_photo_4.png /sdcard/Movies/r2_video_1.mp4; do
  $ADB shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$f" >/dev/null 2>&1
done
sleep 3
echo "images:"; $ADB shell content query --uri content://media/external/images/media --projection _display_name 2>&1 | grep -c r2_photo
echo "videos:"; $ADB shell content query --uri content://media/external/video/media --projection _display_name 2>&1 | grep -c r2_video
echo "=== ios addmedia"
xcrun simctl addmedia "$UDID" "$M/r2_photo_1.png" "$M/r2_photo_2.png" "$M/r2_photo_3.png" "$M/r2_photo_4.png" "$M/r2_video_1.mp4" && echo "ios addmedia ok"
echo "MEDIA PUSH DONE"
