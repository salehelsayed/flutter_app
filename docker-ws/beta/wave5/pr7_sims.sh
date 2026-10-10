#!/bin/bash
# Read-only: build progress + available iOS simulators.
tail -c 600 /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr7_build_${1:-fix}.log | tr '\r' '\n' | tail -6
echo "=== booted ==="; xcrun simctl list devices booted | grep -v '^=='
echo "=== available iPhones ==="; xcrun simctl list devices available | grep -E 'iPhone|-- iOS' | head -20
echo "=== load ==="; sysctl -n vm.loadavg
