#!/bin/bash
# Wait up to 9 min for pr7_sim_test.sh <label> to finish; print its log.
L=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr7_test_${1:-fix}.log
for _ in $(seq 1 108); do grep -qE ' done$|exit 1|missing|failed' "$L" && break; sleep 5; done
cat "$L"
