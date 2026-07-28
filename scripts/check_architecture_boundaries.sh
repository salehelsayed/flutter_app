#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if (($# > 0)); then
  printf 'check_architecture_boundaries.sh does not accept arguments.\n' >&2
  exit 2
fi

cd "$ROOT_DIR"
exec dart run tool/architecture_guard/architecture_boundary_checker_cli.dart \
  check \
  --repo-root "$ROOT_DIR" \
  --manifest \
  "$ROOT_DIR/tool/architecture_guard/architecture_boundary_exceptions.json"
