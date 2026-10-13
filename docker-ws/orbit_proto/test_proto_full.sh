#!/bin/bash
# Like test_proto.sh, but keeps the whole output in last_test.log.
cd "$(dirname "$0")/../.."
SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
"$SDK/bin/flutter" test test/features/orbit/prototypes/orbit_depth_prototype_screen_test.dart "$@" > docker-ws/orbit_proto/last_test.log 2>&1
tail -3 docker-ws/orbit_proto/last_test.log
