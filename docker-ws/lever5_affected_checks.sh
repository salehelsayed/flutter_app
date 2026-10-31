#!/bin/bash
# Affected checks for the lever 5 edits to the Plan 347 custody script, inside build/wt-lever5.
#   host-run bash docker-ws/lever5_affected_checks.sh
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-lever5"; SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"; cd "$W" || exit 3
rc=0; T=/tmp/lever5_aff.$$
for t in scripts/test/android_notification_recovery_completion_adapter_contract_test.sh scripts/test/direct_media_blob_custody_prebuilt_runner_contract_test.sh scripts/test/reliability_simulation_discovery_contract_test.sh; do
  bash "$t" > $T 2>&1; r=$?; echo "$t exit=$r"; [ $r -ne 0 ] && { tail -6 $T; rc=1; }
done
python3 -m pytest -q scripts/test/safe_sims_launcher_test.py > $T 2>&1; r=$?; echo "safe_sims_launcher_test exit=$r"; [ $r -ne 0 ] && { tail -6 $T; rc=1; }
"$SDK/bin/flutter" test test/tool/sims/sims_proof_binding_registry_test.dart > $T 2>&1; r=$?; echo "sims_proof_binding_registry_test exit=$r"; tail -1 $T; [ $r -ne 0 ] && rc=1
rm -f $T; exit $rc
