#!/bin/bash
# Wait up to 9 min for pr7_sim_build.sh <label> to finish; print the result.
L=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr7_build_${1:-fix}.log
for _ in $(seq 1 108); do grep -q 'build exit=' "$L" && break; sleep 5; done
tr '\r' '\n' <"$L" | grep -E 'build exit=|Built |error:|Error|FAILED|copied|pub get|pod install|\.app$' | tail -12
echo "orphans: $(pgrep -f 'dartvm.*build ios' | wc -l | tr -d ' ')  load: $(sysctl -n vm.loadavg)"
