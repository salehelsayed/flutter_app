#!/bin/bash
# Read-only: symlinks under the main tool folders that point into the external drive, and whether they are broken.
for d in "$HOME/development" "$HOME/.gradle" "$HOME/.pub-cache" "$HOME/.android" "$HOME/.maestro" "$HOME/Library/Developer" "$HOME/Library/Android" "$HOME/.cache" "$HOME/go"; do
  [ -e "$d" ] || continue
  find "$d" -maxdepth 4 -type l 2>/dev/null | while read l; do
    t=$(readlink "$l"); case "$t" in (/Volumes/CrucialX9*) [ -e "$l" ] && s=ok || s=BROKEN; echo "$s  ${l/$HOME/~} -> $t";; esac
  done
done
