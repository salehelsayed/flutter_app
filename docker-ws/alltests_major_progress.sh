#!/bin/bash
# Read-only: newest capability logs/proofs in the worktree sims output and active sims children.
w=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims; date
echo "== logs (newest, since ${1:-120} min) =="
find "$w/logs" -maxdepth 1 -type f -mmin -"${1:-120}" 2>/dev/null | xargs ls -lt 2>/dev/null | awk '{print $6,$7,$8,$9}' | sed "s|$w/logs/||" | head -20
echo "== proofs touched =="
find "$w/proofs" -maxdepth 1 -mindepth 1 -mmin -"${1:-120}" 2>/dev/null | sed "s|$w/proofs/||" | head -20
echo "== sims children =="
for p in $(pgrep -f "tool/sims/sims.dart major"); do
  pgrep -P "$p" | while read -r c; do ps -o etime=,command= -p "$c" | cut -c1-150; done
done
