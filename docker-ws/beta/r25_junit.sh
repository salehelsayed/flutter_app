#!/bin/bash
# Read-only: JVM test result counts from the build copy (call package + video_compress), per class of interest.
C=/Volumes/CrucialX9/flutter_app-beta0924
for d in "$C/build/app/test-results/testDebugUnitTest" "$C/android/app/build/test-results/testDebugUnitTest" "$C/build/video_compress/test-results/testDebugUnitTest"; do
  [ -d "$d" ] || continue
  echo "== $d"
  for f in "$d"/TEST-*.xml; do
    n=$(basename "$f" .xml | sed 's/^TEST-//')
    case "$n" in *Notification*|*NativeBridge*|*Monotonic*|*LifecycleController*) grep -oE 'tests="[0-9]+" skipped="[0-9]+" failures="[0-9]+" errors="[0-9]+"' "$f" | head -1 | sed "s#^#$n #";; esac
  done
done
