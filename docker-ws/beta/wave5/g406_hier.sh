#!/bin/bash
# Plan 406: dump on-screen texts/ids on an emulator (Maestro hierarchy), filtered.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
maestro --device "${1:-emulator-5554}" hierarchy 2>/dev/null | grep -oE '"(text|accessibilityText|resource-id|hintText)" *: *"[^"]+"' | sort -u | head -${2:-60}
