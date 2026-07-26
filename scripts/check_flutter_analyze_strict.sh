#!/usr/bin/env bash

set -u
set -o pipefail

if [[ "$#" -ne 0 ]]; then
  echo "Usage: ./scripts/check_flutter_analyze_strict.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT_DIR" || exit 2

package_config="$ROOT_DIR/.dart_tool/package_config.json"
if [[ ! -r "$package_config" || ! -s "$package_config" ]]; then
  echo "Resolved package config is required: $package_config" >&2
  exit 2
fi

dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check
ratchet_status=$?
if [[ "$ratchet_status" -ne 0 ]]; then
  exit "$ratchet_status"
fi

flutter analyze --no-pub --fatal-infos --fatal-warnings
exit $?
