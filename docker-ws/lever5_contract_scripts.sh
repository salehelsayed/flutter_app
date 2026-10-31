#!/bin/bash
# Run the two shell contract tests that read the Plan 347 Go fixture by path, inside build/wt-lever5.
#   host-run bash docker-ws/lever5_contract_scripts.sh
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-lever5"; cd "$W" || exit 3
rc=0
for t in scripts/test/android_notification_recovery_completion_adapter_contract_test.sh scripts/test/direct_media_blob_custody_prebuilt_runner_contract_test.sh; do
  bash "$t" > /tmp/lever5_contract.$$ 2>&1; r=$?; echo "$t exit=$r"; [ $r -ne 0 ] && { tail -8 /tmp/lever5_contract.$$; rc=1; }
done
rm -f /tmp/lever5_contract.$$; exit $rc
