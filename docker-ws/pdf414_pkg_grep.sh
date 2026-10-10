#!/bin/bash
# Plan 414: inspect the file_picker package build script in the pub cache.
D=$(ls -d "$HOME/.pub-cache/hosted/pub.dev/file_picker-11."* | tail -1)
cat "$D/android/build.gradle"
echo "=== app gradle.properties"
cat "$(cd "$(dirname "$0")/.." && pwd)/android/gradle.properties"
