#!/bin/bash
# Read-only: scan the main checkout's untracked files under docker-ws/ for secrets and big files before committing them.
# Prints file names and pattern names only, never matching content.
#   host-run bash docker-ws/main_untracked_scan.sh <out-file-in-repo>
M=/Volumes/CrucialX9/flutter_app; OUT="$M/${1:?out}"
cd "$M" || exit 2
git ls-files -o --exclude-standard -- docker-ws > "$OUT.list"
{
  echo "files=$(wc -l < "$OUT.list")"
  echo "== by extension"; sed -E 's/.*\.([A-Za-z0-9]+)$/\1/' "$OUT.list" | sort | uniq -c | sort -rn | head -15
  echo "== larger than 200 KB"; while read -r f; do s=$(stat -f %z "$f" 2>/dev/null || echo 0); [ "$s" -gt 204800 ] && echo "$s $f"; done < "$OUT.list"
  echo "== secret-like patterns (file: pattern)"
  while read -r f; do
    for p in 'BEGIN [A-Z ]*PRIVATE KEY' 'IPHONE1[13]_PIN=' 'HETZNER_SSH_PASS=' 'TYPESAFE_API_KEY=' 'storePassword' 'keyPassword' 'AKIA[0-9A-Z]{16}' 'ghp_[A-Za-z0-9]{20,}' 'sk-[A-Za-z0-9]{20,}' 'private_key' 'Bearer [A-Za-z0-9._-]{20,}' 'password *[:=]'; do
      grep -E -q -- "$p" "$f" 2>/dev/null && echo "$f: $p"
    done
  done < "$OUT.list"
} > "$OUT" 2>&1
cat "$OUT"
