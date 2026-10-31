#!/bin/bash
# Run one named check inside build/wt-lever5 and print the tail.
#   host-run bash docker-ws/lever5_one.sh discovery|registry|launcher
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-lever5"; SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"; cd "$W" || exit 3
case "$1" in
  discovery) bash scripts/test/reliability_simulation_discovery_contract_test.sh 2>&1 | tail -25 ;;
  registry) "$SDK/bin/flutter" test test/tool/sims/sims_proof_binding_registry_test.dart 2>&1 | grep -v '^\s*$' | tail -30 ;;
  launcher) python3 scripts/test/safe_sims_launcher_test.py 2>&1 | tail -6 ;;
esac
