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

# Plan 347 has exactly two production owners of strict media network calls: the
# prepared sender coordinator and the source-pinned receiver download/ACK
# owner. Schema, transaction, lifecycle, and debug composition may understand
# the typed commitment, but may not bypass either network owner.
readonly STRICT_NETWORK_OWNERS=(
  lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart
  lib/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart
)

# Literal-token scanning alone can miss a caller that forwards strict values
# through variables. Inspect every production call to the three media helpers
# and require the exact owner set whenever strict named arguments are supplied.
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
expected_strict_helper_adopters="$(
  printf '%s\n' "${STRICT_NETWORK_OWNERS[@]}" | sort -u
)"
if [[ "$strict_helper_adopters" != "$expected_strict_helper_adopters" ]]; then
  printf 'expected strict network owners:\n%s\n' \
    "$expected_strict_helper_adopters" >&2
  printf 'actual strict network owners:\n%s\n' \
    "${strict_helper_adopters:-<none>}" >&2
  fail 'strict relay-media custody network owner allowlist changed'
fi

# Keep the wider wire/schema vocabulary bounded to reviewed typed owners. This
# is deliberately separate from the stricter network-helper allowlist above.
readonly STRICT_SCHEMA_OWNERS=(
  lib/core/bridge/p2p_bridge_client.dart
  lib/core/database/direct_media_blob_custody.dart
  lib/core/database/helpers/media_attachments_db_helpers.dart
  lib/core/database/migrations/111_direct_media_blob_custody.dart
  lib/debug/android_direct_media_blob_custody_e2e.dart
  lib/core/media/direct_media_blob_custody.dart
  lib/core/services/inbox_store_outcome.dart
  lib/features/conversation/application/handle_incoming_chat_message_use_case.dart
  lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart
  lib/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart
)
schema_token_owners="$(
  rg -l -g '*.dart' \
    'direct_media_blob_v1|ack_or_expiry_v1|custodyRelayPeerId' lib | sort -u
)"
expected_schema_token_owners="$(
  printf '%s\n' "${STRICT_SCHEMA_OWNERS[@]}" | sort -u
)"
if [[ "$schema_token_owners" != "$expected_schema_token_owners" ]]; then
  printf 'expected strict schema owners:\n%s\n' \
    "$expected_schema_token_owners" >&2
  printf 'actual strict schema owners:\n%s\n' \
    "${schema_token_owners:-<none>}" >&2
  fail 'strict relay-media custody schema owner allowlist changed'
fi

# Plan 348 permits the external-share coordinator to adopt the prepared sender
# owner, but feature producers still may not inline strict wire/schema tokens.
# Keeping this literal-token guard over share/groups/posts allows the reviewed
# coordinator call while continuing to reject a raw strict helper/schema fork.
if rg -n -g '*.dart' \
  'direct_media_blob_v1|ack_or_expiry_v1|custodyRelayPeerId|blobCustody' \
  lib/features/share lib/features/groups lib/features/posts >/dev/null; then
  rg -n -g '*.dart' \
    'direct_media_blob_v1|ack_or_expiry_v1|custodyRelayPeerId|blobCustody' \
    lib/features/share lib/features/groups lib/features/posts >&2 || true
  fail 'feature producer inlined strict blob custody wire/schema ownership'
fi

require_fixed "'MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED'" \
  lib/core/config/direct_media_blob_custody_client_flag.dart
require_fixed 'defaultValue: false' \
  lib/core/config/direct_media_blob_custody_client_flag.dart
if rg -n -g '*.dart' \
  'MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED|kDirectMediaBlobCustodyClientEnabled' \
  lib/core/notifications lib/features/notifications 2>/dev/null; then
  printf '%s\n' "$strict_helper_adopters" >&2
  fail 'strict media custody selector became coupled to push/notification capability'
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

printf 'PASS: relay media ACK-or-expiry custody rollout and bounded Plan 347/348 adopter contract\n'
