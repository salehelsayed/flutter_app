#!/bin/bash
# usage: sim_test_derived_data.sh <worktree>
# Readies and prints the worktree's simulator XCTest DerivedData, the same
# folder the {sim_derived} adapter placeholder uses. MKNOON_SIM_DERIVED_CLEAN=1
# empties it first.
tree="$(cd "$1" && pwd -P)" || exit 2
digest="$(printf '%s' "$tree" | shasum -a 256 | cut -c1-8)"
dir="$HOME/dd-hetzner-test-sim-$(basename "$tree")-$digest"
. "$(dirname "$0")/test_derived_data.sh"
if [ "${MKNOON_SIM_DERIVED_CLEAN:-}" = 1 ]; then rm -rf "$dir"; fi
prepare_test_derived_data "$dir" >&2
echo "$dir"
