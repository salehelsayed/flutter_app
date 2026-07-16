#!/usr/bin/env bash

set -euo pipefail

printf '%s\n' "$*" >>"$SIMS_TEST_CHILD_LOG"
scenario=''
introducer=''
recipient=''
introduced=''
artifact_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --scenario) scenario="$2"; shift 2 ;;
    --introducer) introducer="$2"; shift 2 ;;
    --recipient) recipient="$2"; shift 2 ;;
    --introduced-android) introduced="$2"; shift 2 ;;
    --artifact-dir) artifact_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

exit_code="${SIMS_TEST_CHILD_EXIT:-0}"
[ "$exit_code" -eq 0 ] || exit "$exit_code"
case "$scenario" in
  physical_introducer) test_case='TC-12' ;;
  emulator_introducer) test_case='TC-13' ;;
  *) exit 64 ;;
esac

mkdir -p "$artifact_dir"
printf '%s\n' \
  "{\"testCase\":\"$test_case\",\"scenario\":\"$scenario\",\"status\":\"passed\",\"devices\":[\"$introducer\",\"$recipient\",\"$introduced\"],\"copyExtractor\":\"uiautomator\",\"checks\":{\"targetsDiscovered\":true,\"centralPreparedArtifactInstalled\":true,\"identitiesCollected\":true,\"contactsEstablished\":true,\"introductionSent\":true,\"copyExtractorFeasibility\":true,\"b_acceptIntroducerTerminatedBeforeSend\":true,\"b_acceptIntroducerStillTerminatedBeforeTap\":true,\"b_acceptAcceptanceCopy\":true,\"b_acceptBoundedNodeTap\":true,\"b_acceptFinalPeerIsRecipient\":true,\"b_acceptStatusContext\":true,\"c_acceptIntroducerTerminatedBeforeSend\":true,\"c_acceptIntroducerStillTerminatedBeforeTap\":true,\"c_acceptAcceptanceCopy\":true,\"c_acceptBoundedNodeTap\":true,\"c_acceptFinalPeerIsRecipient\":true,\"c_acceptStatusContext\":true,\"zeroNavigationErrors\":true}}" \
  >"$artifact_dir/$scenario.json"
printf '%s\n' 'child diagnostic'
