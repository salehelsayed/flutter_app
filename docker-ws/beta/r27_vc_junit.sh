#!/bin/bash
# All video_compress JVM test classes in the build copy with counts.
C=/Volumes/CrucialX9/flutter_app-beta0924/build/video_compress/test-results/testDebugUnitTest
for f in "$C"/TEST-*.xml; do n=$(basename "$f" .xml | sed 's/^TEST-//'); grep -oE 'tests="[0-9]+" skipped="[0-9]+" failures="[0-9]+" errors="[0-9]+"' "$f" | head -1 | sed "s#^#$n #"; done
