#!/bin/bash
# Which otaliastudios Transcoder version video_compress 3.1.4 uses, and whether the Gradle cache has its sources.
P=$HOME/.pub-cache/hosted/pub.dev/video_compress-3.1.4
grep -n "transcoder\|otaliastudios" "$P/android/build.gradle"
find $HOME/.gradle/caches/modules-2/files-2.1/com.otaliastudios -maxdepth 3 2>/dev/null | head -20
