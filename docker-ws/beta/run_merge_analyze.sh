#!/bin/bash
# flutter analyze on the Dart files the beta-fix merge changed (live checkout, Flutter 3.47.2).
H="$(cd "$(dirname "$0")" && pwd)"
cd /Volumes/CrucialX9/flutter_app || exit 2
bash docker-ws/flutter_sdk.sh analyze --no-fatal-infos $(cat "$H/merge_dart_files.txt") 2>&1 | tail -15
echo "ANALYZE DONE"
