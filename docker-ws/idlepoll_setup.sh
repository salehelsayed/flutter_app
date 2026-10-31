#!/bin/bash
# Copy ignored build inputs into the idle-poll check worktree from the Codex-UI audio worktree (fallback: astra-c worktree). Prints sha prefixes only.
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-idlepoll; M=/Volumes/CrucialX9/flutter_app
A=$M/build/wt-cui-audio; B=$M/build/wt-astra-c
echo "prior audio worktree present: $([ -d "$A" ] && echo yes || echo no)"
for f in android/app/google-services.json android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/libs/GoMknoon.inputs.sha256 android/local.properties android/key.properties; do
  src=""; for base in "$A" "$B" "$M"; do [ -f "$base/$f" ] && { src="$base/$f"; break; }; done
  if [ -n "$src" ]; then mkdir -p "$(dirname "$W/$f")"; cp "$src" "$W/$f"; echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f <- ${src%%/android/*}"; else echo "MISSING $f"; fi
done
