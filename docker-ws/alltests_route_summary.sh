#!/bin/bash
# Read-only: per-route outcome summary for a legacy routes dir (non-empty logs only).
d="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$1/full-sims-0-routes/logs"
pass=0; fail=""; other=0
for f in "$d"/*.log; do [ -s "$f" ] || continue
  if grep -qE "Some tests failed|\*\* TEST (EXECUTE )?FAILED|^FAIL:" "$f"; then fail="$fail $(basename $f)"
  elif grep -q "All tests passed\|PASS" "$f"; then pass=$((pass+1)); else other=$((other+1)); fi
done
echo "non-empty logs: $(find "$d" -name '*.log' -size +0 | wc -l) pass=$pass other=$other fail:$fail"
