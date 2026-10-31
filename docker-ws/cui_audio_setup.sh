#!/bin/bash
# Copy ignored build inputs into the Codex-UI audio worktree from the prior Codex-UI audio worktree (fallback: b376 worktree). Prints sha prefixes only.
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-cui-audio; M=/Volumes/CrucialX9/flutter_app
A=/Volumes/CrucialX9/flutter_app_plan407_audio_resume; B=$M/build/wt-cui-b376
echo "prior audio worktree present: $([ -d "$A" ] && echo yes || echo no)"
for f in android/app/google-services.json android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/libs/GoMknoon.inputs.sha256 android/local.properties android/key.properties; do
  src=""; for base in "$A" "$B" "$M"; do [ -f "$base/$f" ] && { src="$base/$f"; break; }; done
  if [ -n "$src" ]; then mkdir -p "$(dirname "$W/$f")"; cp "$src" "$W/$f"; echo "$(shasum -a 256 "$W/$f" | cut -c1-16) $f <- ${src%%/android/*}"; else echo "MISSING $f"; fi
done
