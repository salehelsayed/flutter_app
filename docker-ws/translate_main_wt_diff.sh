#!/bin/bash
# Read-only: diff of one tracked path in build/wt-translate-main.   host-run bash docker-ws/translate_main_wt_diff.sh <path>
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-main && git diff -- "${1:?path}" | head -60
