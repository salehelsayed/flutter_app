#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_fixed() {
  local needle="$1"
  shift
  rg -Fq -- "$needle" "$@" ||
    fail "missing required rollout contract: $needle"
}

readonly RELAY_README="go-relay-server/README.md"
readonly COMPAT_DOC="Network-Arch/Transport-Reliability/07-relay-backward-compatibility.md"
readonly OPS_RUNBOOK="Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-10-durable-inbox-redis-pool-ops-runbook.md"
readonly DASHBOARD="go-relay-server/grafana-relay-dashboard.json"
readonly GATE_SCRIPT="scripts/run_test_gates.sh"

for doc in "$RELAY_README" "$COMPAT_DOC" "$OPS_RUNBOOK"; do
  require_fixed 'DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED' "$doc"
  require_fixed 'ack_or_expiry_v1' "$doc"
done

for action in \
  store_custody_v1 \
  retrieve_custody_pending_v1 \
  ack_custody_v1; do
  require_fixed "$action" "$COMPAT_DOC"
done

for state in S0 S1 S2 S3; do
  require_fixed "$state" "$OPS_RUNBOOK"
done

require_fixed 'custody_inbox:' "$COMPAT_DOC" "$OPS_RUNBOOK"
require_fixed 'actual Redis restart/restore' "$OPS_RUNBOOK"
require_fixed 'pinned old-binary' "$OPS_RUNBOOK"
require_fixed 'flag off' "$OPS_RUNBOOK"

for metric in \
  relay_inbox_custody_contract_info \
  relay_inbox_custody_admission_enabled \
  relay_inbox_custody_messages_pending \
  relay_inbox_custody_expired_total \
  relay_inbox_custody_store_total; do
  require_fixed "$metric" go-relay-server/metrics.go
  require_fixed "$metric" "$DASHBOARD"
done

require_fixed 'run_ack_custody_go_gate()' "$GATE_SCRIPT"
require_fixed 'direct_mutation_v109' \
  lib/core/services/inbox_store_outcome.dart \
  go-relay-server/ack_custody.go \
  go-mknoon/node/inbox.go
require_fixed 'TestInboxAckCustodyMixedRelayAndProofContract' "$GATE_SCRIPT"
require_fixed 'TestInboxAckCustodyReceiveFanoutContract' "$GATE_SCRIPT"
require_fixed 'TestInboxAckCustodyMediaExpiryCeiling' "$GATE_SCRIPT"
require_fixed 'TestDispatchInboxAckCustodyContract' "$GATE_SCRIPT"
require_fixed 'TestInboxStoreMediaExpiryCeilingBridgeContract' "$GATE_SCRIPT"
require_fixed 'TestRelayNotificationClosure_DirectMediaEnvelopeExpiryCeiling' "$GATE_SCRIPT"
require_fixed 'TestRelayNotificationClosure_DirectMutationCustody' "$GATE_SCRIPT"
require_fixed "go test ./bridge ./node -run 'GPL12|GK030|TC3410|TC363'" "$GATE_SCRIPT"
require_fixed 'TestTC363GroupProtectedCustodyKinds' \
  go-mknoon/node/inbox_ack_custody_test.go
require_fixed 'TestRelayNotificationClosure_GroupProtectedCustodyKinds' \
  go-relay-server/ack_custody_protocol_test.go
require_fixed 'TestAckCustodyMixedVersionMatrix' "$GATE_SCRIPT"
require_fixed 'TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace' "$GATE_SCRIPT"
require_fixed 'go_binding_staleness_contract_test.sh' "$GATE_SCRIPT"

call_sites="$(rg -n '^[[:space:]]*run_ack_custody_go_gate([[:space:]]|$)' "$GATE_SCRIPT" || true)"
[ "$(printf '%s\n' "$call_sites" | rg -c . || true)" -ge 2 ] ||
  fail 'ack-custody Go gate must be invoked from both 1to1 and all'

jq empty "$DASHBOARD"

printf 'PASS: relay ACK-custody rollout contract\n'
