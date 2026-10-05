#!/bin/bash
# Read-only: booted simulators with runtime, and Mac load.
xcrun simctl list devices booted 2>/dev/null
echo "--- load: $(sysctl -n vm.loadavg)"
