#!/bin/bash
# Read-only: size breakdown of artifacts/ on the Mac (faster than the container mount).
cd "$(dirname "$0")/.."
echo "== top level"; du -sh artifacts/* 2>/dev/null | sort -rh | head -20
for d in $(du -s artifacts/* 2>/dev/null | sort -rn | head -6 | awk '{print $2}'); do
  echo "== $d (largest entries)"; du -sh "$d"/* 2>/dev/null | sort -rh | head -6
done
echo "== largest single files"; find artifacts -type f -size +300M -exec ls -lh {} + 2>/dev/null | awk '{print $5, $9}' | sort -rh | head -15
echo "== file counts"; for d in artifacts/*/; do printf "%8d %s\n" "$(find "$d" | wc -l)" "$d"; done | sort -rn | head -8
