#!/bin/bash
# Plan 414: copy the received PDFs out of the iPhone 13 app container and hash them.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/Test-Flight-Improv/evidence/414/e2e/iphone13_pull"; mkdir -p "$D"
U=00008110-00184D622289801E
for rel in "$@"; do
  xcrun devicectl device copy from --device $U --domain-type appDataContainer --domain-identifier com.mknoon.app \
    --source "Documents/media/$rel" --destination "$D/$(basename "$rel")" >/dev/null 2>&1 && echo "pulled $rel"
done
shasum -a 256 "$D"/*.pdf "$ROOT/Test-Flight-Improv/evidence/414/e2e/fixtures/"*.pdf | sed "s#$ROOT/##"
