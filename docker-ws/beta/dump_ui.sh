#!/bin/bash
# Dump Maestro UI hierarchy of both devices into the current run dir.
# Usage: dump_ui.sh <label> [ios|android|both]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L=${1:-ui}; W=${2:-both}
mkdir -p "$RUN/ui"
if [ "$W" != ios ]; then timeout 120 maestro --device "$SERIAL" hierarchy > "$RUN/ui/${L}_android.json" 2>&1; fi
if [ "$W" != android ]; then timeout 200 maestro --device "$UDID" hierarchy > "$RUN/ui/${L}_ios.json" 2>&1; fi
ls -la "$RUN/ui" | grep "$L"
