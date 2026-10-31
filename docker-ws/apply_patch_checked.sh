#!/usr/bin/env bash
# Apply one Codex patch on local main only if size/sha, base tree and result tree all match; then commit.
#   host-run bash docker-ws/apply_patch_checked.sh <patch src> <sha256> <base tree> <result tree> <commit msg file>
set -euo pipefail
SRC="$1"; WANT_SHA="$2"; BASE_TREE="$3"; WANT_TREE="$4"; MSG="$5"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/build/kayan-safe/fixround"; mkdir -p "$OUT"
P="$OUT/$(basename "$SRC")"
cp "$SRC" "$P"
cd "$REPO"
sha=$(shasum -a 256 "$P" | awk '{print $1}')
echo "patch=$(basename "$P") size=$(wc -c < "$P" | tr -d ' ') sha=$sha"
[ "$sha" = "$WANT_SHA" ] || { echo "FAIL sha"; exit 3; }
head_tree=$(git rev-parse 'HEAD^{tree}')
[ "$head_tree" = "$BASE_TREE" ] || { echo "FAIL base tree $head_tree"; exit 3; }
[ -z "$(git diff --cached --name-only)" ] || { echo "FAIL index not empty"; exit 3; }
git apply --numstat "$P" | awk '{print "  " $3}'
TMPIDX="$OUT/tmp.index"; rm -f "$TMPIDX"
GIT_INDEX_FILE="$TMPIDX" git read-tree HEAD
GIT_INDEX_FILE="$TMPIDX" git apply --cached "$P"
tree=$(GIT_INDEX_FILE="$TMPIDX" git write-tree); rm -f "$TMPIDX"
echo "tree=$tree"
[ "$tree" = "$WANT_TREE" ] || { echo "FAIL tree"; exit 4; }
git update-index -q --refresh || true
git apply --check "$P"
git apply --index "$P"
got=$(git write-tree)
[ "$got" = "$WANT_TREE" ] || { echo "FAIL staged tree $got"; exit 5; }
git commit -q -F "$MSG"
echo "committed $(git log --oneline -1) tree=$(git rev-parse 'HEAD^{tree}')"
