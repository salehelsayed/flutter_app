#!/bin/bash
# Run an iOS flow and an Android flow AT THE SAME TIME (they sync through the
# app itself, e.g. waiting for the other side's message).
# Usage: pair.sh <label> <ios-flow|-> <android-flow|-> [KEY=VAL ...]
H="$(dirname "$0")"
LABEL=$1; IF=$2; AF=$3; shift 3
[ "$IF" != - ] && { bash "$H/run_flow.sh" ios "$IF" "$LABEL" "$@" & }
[ "$AF" != - ] && { bash "$H/run_flow.sh" android "$AF" "$LABEL" "$@" & }
wait
