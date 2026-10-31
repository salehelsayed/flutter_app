#!/bin/bash
# Copy ignored build inputs into the Codex-UI b376 worktree and print their sha256 prefixes (no contents).
set -euo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-b376; M=/Volumes/CrucialX9/flutter_app; N=/Volumes/CrucialX9/flutter_app_plan407_notification_final
cp "$N/android/app/google-services.json" "$W/android/app/google-services.json"
cp "$M/android/local.properties" "$W/android/local.properties"
cp "$M/android/key.properties" "$W/android/key.properties"
for src in "$N/android/app/libs/GoMknoon.aar" "$M/android/app/libs/GoMknoon.aar"; do [ -f "$src" ] && echo "aar-candidate $(shasum -a 256 "$src" | cut -c1-16) $src"; done
[ -f "$N/android/app/libs/GoMknoon.inputs.sha256" ] && echo "notification_final inputs stamp: $(cat "$N/android/app/libs/GoMknoon.inputs.sha256" | cut -c1-16)"
mkdir -p "$W/android/app/libs"; cp "$N/android/app/libs/GoMknoon.aar" "$W/android/app/libs/GoMknoon.aar"; [ -f "$N/android/app/libs/GoMknoon-sources.jar" ] && cp "$N/android/app/libs/GoMknoon-sources.jar" "$W/android/app/libs/"; [ -f "$N/android/app/libs/GoMknoon.inputs.sha256" ] && cp "$N/android/app/libs/GoMknoon.inputs.sha256" "$W/android/app/libs/"
for f in android/app/google-services.json android/local.properties android/key.properties android/app/libs/GoMknoon.aar; do echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f"; done
