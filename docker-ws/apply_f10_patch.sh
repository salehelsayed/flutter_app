#!/usr/bin/env bash
# Usage: apply_f10_patch.sh check|apply
# check: copy the F10 patch into build/kayan-safe/f10, verify size + sha256,
#        and compute the tree it yields on HEAD in a throwaway index.
# apply: same checks, then apply to the working tree + index and commit.
set -euo pipefail
MODE="${1:-check}"
echo "mode=$MODE args=$#"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC=/Volumes/CrucialX9/flutter_app_codex_pr15_t3elbg1o/.codex-test-logs/F10-host-fixes-20261018/F10-host-fixes.patch
OUT="$REPO/build/kayan-safe/f10"
WANT_SHA=dbb3b6709548e3943001738dcfcf5db504676bb01298e6e724dde649967e86ff
WANT_SIZE=69950
WANT_TREE=47e0ddcaa96b38fbe670aef9261eb13ceb76521c
WANT_HEAD=c8184d943
mkdir -p "$OUT"
cp "$SRC" "$OUT/F10-host-fixes.patch"
P="$OUT/F10-host-fixes.patch"
cd "$REPO"
size=$(wc -c < "$P" | tr -d ' ')
sha=$(shasum -a 256 "$P" | awk '{print $1}')
head=$(git rev-parse --short=9 HEAD)
echo "head=$head size=$size sha=$sha"
[ "$head" = "$WANT_HEAD" ] || { echo "FAIL head"; exit 3; }
[ "$size" = "$WANT_SIZE" ] || { echo "FAIL size"; exit 3; }
[ "$sha" = "$WANT_SHA" ] || { echo "FAIL sha"; exit 3; }
[ -z "$(git diff --cached --name-only)" ] || { echo "FAIL index not empty"; exit 3; }
echo "=== files in patch ==="
git apply --numstat "$P"
TMPIDX="$OUT/tmp.index"
rm -f "$TMPIDX"
GIT_INDEX_FILE="$TMPIDX" git read-tree HEAD
GIT_INDEX_FILE="$TMPIDX" git apply --cached "$P"
tree=$(GIT_INDEX_FILE="$TMPIDX" git write-tree)
rm -f "$TMPIDX"
echo "tree=$tree"
[ "$tree" = "$WANT_TREE" ] || { echo "FAIL tree"; exit 4; }
echo "TREE OK"
[ "$MODE" = apply ] || exit 0
git update-index -q --refresh || true
git apply --check "$P"
git apply --index "$P"
got=$(git write-tree)
[ "$got" = "$WANT_TREE" ] || { echo "FAIL staged tree $got"; exit 5; }
git commit -q -F "$OUT/commit-msg.txt"
git log --oneline -1
echo "committed tree=$(git rev-parse HEAD^{tree})"
