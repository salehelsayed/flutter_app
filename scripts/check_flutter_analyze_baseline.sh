#!/usr/bin/env bash

set -u

if [[ "$#" -ne 0 ]]; then
  echo "Usage: ./scripts/check_flutter_analyze_baseline.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
exec "$ROOT_DIR/scripts/check_flutter_analyze_strict.sh"
