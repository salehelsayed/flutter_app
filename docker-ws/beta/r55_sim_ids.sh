#!/bin/bash
# Read-only: the named simulators and their runtime/state.
xcrun simctl list devices 2>/dev/null | grep -E "$1"
