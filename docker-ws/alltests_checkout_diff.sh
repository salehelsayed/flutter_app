#!/bin/bash
# Read-only: compare tracked+modified source between main checkout and the all-tests worktree.
m=/Volumes/CrucialX9/flutter_app; w=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
for d in lib test integration_test tool scripts ios/Runner ios/RunnerUITests android/app/src go-mknoon go-relay-server .claude/skills/sims docs/testing; do
  out=$(diff -rq -x build -x .dart_tool -x '__pycache__' -x '*.pyc' -x Pods -x .gradle "$m/$d" "$w/$d" 2>&1 | head -8)
  [ -n "$out" ] && { echo "== $d =="; echo "$out"; }
done
echo "== pubspec =="; cmp "$m/pubspec.yaml" "$w/pubspec.yaml" && cmp "$m/pubspec.lock" "$w/pubspec.lock" && echo same
grep -o '"root": *"[^"]*"' /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/source066-sims/plan.json | head -2
head -5 /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/source066-sims.wrapper.log 2>/dev/null | cut -c1-200
