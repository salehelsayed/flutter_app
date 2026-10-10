#!/bin/bash
# Read-only: any symlink under the usual tool folders (and the repo's .claude) that points into the given paths.
for d in "$HOME/development" "$HOME/.gradle" "$HOME/.pub-cache" "$HOME/.android" "$HOME/Library/Developer" "$HOME/Library/Android" "$HOME/.cache" "$HOME/go" "$HOME/.maestro" /Volumes/CrucialX9/flutter_app/.claude; do
  [ -e "$d" ] || continue
  find "$d" -maxdepth 5 -type l 2>/dev/null | while read l; do t=$(readlink "$l"); for p in "$@"; do case "$t" in ("$p"*) echo "LINK ${l/$HOME/~} -> $t";; esac; done; done
done
echo "scan done"
