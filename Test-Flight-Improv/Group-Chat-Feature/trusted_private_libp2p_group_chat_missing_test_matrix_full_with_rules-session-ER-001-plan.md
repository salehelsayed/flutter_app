# ER-001 Session Plan - Invalid signature diagnostics are privacy-safe and actionable

Status: covered

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:24:00+02:00 | Local planner completed | ER-001 source matrix row; ordered-session ER-001 row; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_authorization_forward_test.go`; `go-mknoon/node/pubsub_test.go`; `lib/core/bridge/go_bridge_client.dart`; `test/core/bridge/go_bridge_client_test.dart` | The missing row-owned gap is app-visible, privacy-safe invalid-signature diagnostics for the shipped validator event families. Implement a hashed `group:validation_rejected` diagnostic event from the Go validator and bridge it into Flutter's existing group diagnostics stream. | Patch Go validator diagnostics and bridge forwarding, then run focused Go and Dart proofs. |

## real scope

ER-001 asks for invalid signature rejection diagnostics that are useful without leaking group identifiers, peer identifiers, signatures, ciphertext, nonces, plaintext, group names, or sensitive addresses. The shipped event-family scope is the current group envelope validator surface: normal messages, reactions, membership system events, metadata updates, dissolve events, and key rotation events.

## closure bar

ER-001 can move to `Covered` when:

- invalid signatures across shipped event families reject before accepted group delivery
- Go logs and app-visible diagnostics include useful fields such as reason, envelope type, epoch, and hashed actor/group identifiers
- diagnostics are rate-limited and contain no raw secret material, plaintext, peer IDs, group IDs, group names, signatures, ciphertext, nonces, or multiaddrs
- Flutter bridge diagnostics receive the validation reject event without invoking normal group-message callbacks

## session classification

`evidence-gated`, resolved with row-owned Go/raw-validator proof plus focused bridge forwarding proof.

## Device/Relay Proof Profile

- Profile for this session: host-only Go validator proof and Flutter bridge event-routing proof.
- The source row marks 3-party E2E as N/A; real-device relay proof is supplemental and was not required for this closure.

## files touched

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

## exact tests and gates run

- `cd go-mknoon && go test ./node -run 'TestER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -v` passed.
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group validation reject push event reaches diagnostics stream without invoking group message callback'` passed.
- `git diff --check` must pass after closure docs.

## positive evidence

- `pubsub.go` now emits `group:validation_rejected` from the same rate-limited validator rejection path that writes hashed diagnostic logs.
- The diagnostic payload carries only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`.
- `TestER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable` injects invalid signatures for messages, reactions, `member_added`, `members_added`, `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`, then proves each rejects, logs one actionable diagnostic, emits one app-visible diagnostic, and omits raw sensitive fragments.
- The existing security-family validator proof still confirms invalid signatures reject across the same shipped event families.
- `GoBridgeClient` forwards `group:validation_rejected` to `groupDiagnosticEventStream` without calling the group-message callback.

## caveats

- ER-001 covers shipped validator event families. Event families that do not yet have first-class production models, such as bans, remote deletes, receipts, and commit/key-package transitions, remain owned by DB-012/EK-012-style prerequisite rows until modeled or scoped out.
- This is a diagnostics-stream closure, not a new snackbar or conversation-banner UX.

## done criteria

- Source matrix ER-001 moves from `Partial` to `Covered` with the concrete Go and Flutter bridge evidence above.
- `test-inventory.md` records the ER-001 crosswalk.
- Breakdown current-session state, evidence map, inventory, ledger, ordered row, and source counts record ER-001 as accepted/Covered.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:28:00+02:00 | Local executor completed | `pubsub.go`; `pubsub_authorization_forward_test.go`; `go_bridge_client.dart`; `go_bridge_client_test.dart` | Implemented privacy-safe hashed validation-reject diagnostics and bridge forwarding. Focused Go and Flutter tests passed. | Persist ER-001 as `Covered` in source and closure docs. |

## Final Execution Verdict

Covered on 2026-05-01. ER-001 is covered for the shipped group validator event families by privacy-safe hashed Go logs, app-visible validation reject diagnostics, rate-limited diagnostic emission, and Flutter bridge forwarding into the group diagnostics stream without normal group-message callback side effects.
