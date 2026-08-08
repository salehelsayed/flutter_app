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
    fail "missing required relay-media custody contract: $needle"
}

readonly RELAY_README="go-relay-server/README.md"
readonly DASHBOARD="go-relay-server/grafana-relay-dashboard.json"
readonly METRICS_SOURCE="go-relay-server/metrics.go"
readonly GATE_SCRIPT="scripts/run_test_gates.sh"

for token in \
  DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED \
  direct_media_blob_v1 \
  ack_or_expiry_v1 \
  upload_custody_v1 \
  ack_custody_v1 \
  .custody-v1; do
  require_fixed "$token" "$RELAY_README"
done

require_fixed 'relay-first rollout' "$RELAY_README"
require_fixed 'roll forward' "$RELAY_README"
require_fixed 'There is no protected list action.' "$RELAY_README"

for metric in \
  relay_media_custody_contract_info \
  relay_media_custody_admission_enabled \
  relay_media_custody_blobs_pending \
  relay_media_custody_bytes_pending \
  relay_media_custody_tombstones \
  relay_media_custody_outcomes_total; do
  require_fixed "$metric" "$METRICS_SOURCE"
  require_fixed "$metric" "$DASHBOARD"
done

require_fixed 'run_media_custody_go_gate()' "$GATE_SCRIPT"
require_fixed "-list '^TestRelayNotificationClosure_DirectMediaBlobCustody'" "$GATE_SCRIPT"
require_fixed "go test -race ." "$GATE_SCRIPT"
require_fixed 'TestDirectMediaBlobCustodySurvivesRelayProcessHandoff' "$GATE_SCRIPT"
require_fixed 'UploadPhaseAwareRelaySelection' "$GATE_SCRIPT"
require_fixed 'StrictDownloadSelectsExactProof' "$GATE_SCRIPT"
require_fixed 'AckPinsSourceRelayAndRequiresExactProof' "$GATE_SCRIPT"
require_fixed 'TestDispatchMediaCustodyContract' "$GATE_SCRIPT"
require_fixed 'TestMediaCustodyMixedRelayMatrix' "$GATE_SCRIPT"
require_fixed 'relay_media_custody_contract_test.sh' "$GATE_SCRIPT"

call_sites="$(
  rg -n '^[[:space:]]*run_media_custody_go_gate([[:space:]]|$)' \
    "$GATE_SCRIPT" || true
)"
[ "$(printf '%s\n' "$call_sites" | rg -c . || true)" -eq 2 ] ||
  fail 'media-custody Go gate must have exactly two dispatch call sites'

for parent_gate in 1to1 all; do
  gate_block="$(
    awk -v marker="$parent_gate)" '
      !inside && $1 == marker { inside = 1 }
      inside { print }
      inside && $1 == ";;" { closed = 1; exit }
      END { if (!inside || !closed) exit 91 }
    ' "$GATE_SCRIPT"
  )" || fail "could not parse $parent_gate gate dispatch block"
  call_count="$(
    printf '%s\n' "$gate_block" |
      rg -c '^[[:space:]]*run_media_custody_go_gate([[:space:]]|$)' || true
  )"
  [ "$call_count" -eq 1 ] ||
    fail "media-custody Go gate must run exactly once under $parent_gate"
done

# Plan 346 exposes a bridge/native primitive only. These exact strict-custody
# tokens must stay out of feature production until a later, separately reviewed
# adopter owns exact ciphertext reuse and envelope/blob expiry coupling. Keep
# the tokens narrow: Plan 345 legitimately uses generic media-custody language.
readonly STRICT_ADOPTER_TOKENS=(
  direct_media_blob_v1
  upload_custody_v1
  ack_custody_v1
  custodyRelayPeerId
  MEDIA_CUSTODY_COMMIT_INDETERMINATE
)

for token in "${STRICT_ADOPTER_TOKENS[@]}"; do
  production_hits="$(
    rg -n -F -g '!lib/core/bridge/p2p_bridge_client.dart' -- "$token" lib || true
  )"
  if [[ -n "$production_hits" ]]; then
    printf '%s\n' "$production_hits" >&2
    fail "strict relay-media custody token escaped its bridge boundary: $token"
  fi
done

# Literal-token scanning alone can miss a caller that forwards strict values
# through variables. Inspect every production call to the three media helpers
# and reject any use of their new strict named arguments outside the bridge.
strict_helper_adopters="$({
  while IFS= read -r dart_file; do
    perl -0777 -ne '
      while (/callP2PMedia(?:Upload|Download|Delete)\((.*?)\);/sg) {
        if ($1 =~ /(?:custodyContract|custodyKind|custodyRelayPeerId|contentHash|expiresAtMs)\s*:/) {
          print "$ARGV\n";
          last;
        }
      }
    ' "$dart_file"
  done < <(rg --files -g '*.dart' -g '!lib/core/bridge/p2p_bridge_client.dart' lib)
} | sort -u)"
if [[ -n "$strict_helper_adopters" ]]; then
  printf '%s\n' "$strict_helper_adopters" >&2
  fail 'strict relay-media custody arguments have a production helper adopter'
fi

# Make the guard non-vacuous: each protected wire/native token must exist at its
# intended lower-layer boundary instead of passing merely because no code uses
# the primitive.
require_fixed 'direct_media_blob_v1' \
  go-relay-server/media.go go-relay-server/media_custody.go
require_fixed 'direct_media_blob_v1' go-mknoon/node/media.go
require_fixed 'upload_custody_v1' \
  go-relay-server/media.go go-relay-server/media_custody.go
require_fixed 'upload_custody_v1' go-mknoon/node/media.go
require_fixed 'ack_custody_v1' \
  go-relay-server/media.go go-relay-server/media_custody.go
require_fixed 'ack_custody_v1' go-mknoon/node/media.go
require_fixed 'custodyRelayPeerId' \
  go-mknoon/bridge/bridge.go lib/core/bridge/p2p_bridge_client.dart
require_fixed 'MEDIA_CUSTODY_COMMIT_INDETERMINATE' go-mknoon/node/media.go

jq empty "$DASHBOARD"

printf 'PASS: relay media ACK-or-expiry custody rollout and no-adopter contract\n'
