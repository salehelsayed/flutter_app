#!/bin/bash
# Remove only the SPM SourcePackages cache of the internal-disk device DerivedData so the next build re-resolves
# binary artifacts (an emptied artifacts dir with a stale workspace-state makes xcodebuild skip the download).
D="$HOME/tmp-dd-device/SourcePackages"
[ -d "$D" ] || { echo "no $D"; exit 0; }
cat "$D/workspace-state.json" 2>/dev/null | head -c 0
rm -rf "$D" && echo "removed $D"
