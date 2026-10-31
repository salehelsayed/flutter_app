#!/bin/bash
# List (or with "delete" remove) WDA xcresult bundles created after 2026-10-23 10:25Z by the T011 Appium attempts.
D=/Volumes/CrucialX9/mac-development/xcode-derived-data/WebDriverAgent-gkkiiuvnweforsdihdsaljhfmztm/Logs/Test
touch -t 202610231225 /tmp/t011_ref   # local CEST = 10:25Z
find "$D" -maxdepth 1 -name "*.xcresult" -newer /tmp/t011_ref -print | while read -r r; do
  echo "$(du -sh "$r" | cut -f1) $(basename "$r")"; [ "${1:-}" = delete ] && rm -rf "$r" && echo "  deleted"
done
