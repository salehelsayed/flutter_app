#!/bin/bash
# Kayan decisions 10-31 for the main checkout leftovers, then the Astra P0 merge:
#  1. commit docs/testing/TESTING.md + scripts/run_claude_docker.sh + its contract test as the --init docker fix
#  2. commit info.plist (date stamp) on its own
#  3. add artifacts/ and s0.png to .git/info/exclude (local only, nothing deleted or opened)
#  4. merge <astra sha> (test/docs-only) with --no-ff
#   host-run bash docker-ws/main_commit_leftovers_and_merge.sh <expected main sha> <astra sha>
set -uo pipefail
EXP=${1:?expected main}; A=${2:?astra sha}
M=/Volumes/CrucialX9/flutter_app; cd "$M" || exit 2
CO="Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse "$EXP")" ] || { echo "STOP local main moved"; exit 4; }
git reset -q
git add -- docs/testing/TESTING.md scripts/run_claude_docker.sh scripts/test/run_claude_docker_update_contract_test.sh
git commit -q -m "chore(docker): run Claude containers with --init (zombie cleanup)" -m "$CO"; echo "docker commit exit=$? $(git rev-parse --short HEAD)"
git add -- info.plist
git commit -q -m "chore: info.plist stamp" -m "$CO"; echo "plist commit exit=$? $(git rev-parse --short HEAD)"
X=.git/info/exclude
grep -qx 'artifacts/' "$X" || echo 'artifacts/' >> "$X"
grep -qx '/s0.png' "$X" || echo '/s0.png' >> "$X"
echo "exclude added: $(grep -cE '^(artifacts/|/s0.png)$' "$X")"
OUT=$(git diff --name-only "$(git merge-base HEAD "$A")" "$A" | grep -vE '^(test|integration_test|docs)/')
[ -z "$OUT" ] || { echo "STOP branch touches non-test files"; echo "$OUT"; exit 6; }
git merge --no-ff "$A" -m "merge: Astra's P0 host journeys and native evidence boundaries" -m "$CO" 2>&1 | tail -3
echo "merge exit=${PIPESTATUS[0]} head=$(git rev-parse HEAD) parents=$(git log -1 --format=%p)"
echo "== status after"; git status --porcelain=v1 --untracked-files=normal
git log --oneline -5
