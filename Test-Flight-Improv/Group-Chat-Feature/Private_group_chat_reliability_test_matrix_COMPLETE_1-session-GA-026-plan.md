# Private Group Chat Reliability Matrix - Session GA-026 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-14 00:22 CEST - Local gap-closure pass reached GA-026 after GA-018 closure. Source matrix row GA-026 was `Open`; session ledger row 194 was `implementation-ready` / `needs_tests_only`; no adjacent GA-026 plan existed. Inspected the source row, session ledger, `go-mknoon/node/pubsub.go::logPubSubValidationReject`, all current validator rejection call sites, and existing GO-008/ER-001 privacy diagnostics coverage.
- 2026-05-14 00:32 CEST - Implemented and validated the exact row-owned all-reason diagnostic privacy proof. Source matrix row GA-026 is now `Covered`; session ledger row 194 is now `covered/accepted`.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GA-026 | Validation rejection diagnostics are privacy-safe | Covered | covered/accepted |

## Gap Classification

`needs_tests_only`.

Current production code already emits validation rejection logs and `group:validation_rejected` events using only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`. Prior GO-008/ER-001 evidence proved adjacent privacy behavior, but GA-026 still lacked exact proof that every validator reject reason preserves the same redaction contract and does not expose raw IDs, keys, signatures, nonces, ciphertext, message IDs, or plaintext markers.

## Scope

Owned files:

- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Production validator behavior changes unless the exact privacy proof exposes a leak.
- Dart/Flutter role authorization files; the row is native diagnostic privacy and the relevant bridge forwarding behavior is already covered by ER-001/GO-008.
- Device-lab or relay-backed harness changes; the row is host-native and has 3-Party E2E marked N/A.

## Implementation Plan

1. Add an exact Go regression that invokes validation rejection diagnostics for every current reject reason emitted by the group topic validator.
2. Use sensitive raw group, sender, local peer, transport peer, message id, device id, key package, public key, signature, ciphertext, nonce, and plaintext marker fragments as leak sentinels.
3. Assert each diagnostic event contains only the allowed key set, each hash field is a 12-character lowercase hex digest or `none`, and the log line uses the same hashed identifiers.
4. Run focused GA-026 tests, adjacent validator/authorization selectors, selected race proof, named groups gate, gofmt, and diff hygiene.
5. Update the source matrix, breakdown ledger, plan verdict, and test inventory with concrete evidence before accepting the row.

## Acceptance Bar

- Source matrix row GA-026 is `Covered`.
- Session ledger row 194 is `covered/accepted`.
- Tests include an exact `GA-026` selector covering every current validation rejection reason.
- Evidence records focused selector, adjacent Go gates, selected race proof, named groups gate, and `git diff --check`.
- Residual-only entry is `none`; no unresolved row-owned blocker remains.

## Execution Evidence

Implemented `go-mknoon/node/pubsub_authorization_forward_test.go::TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons`. The test emits diagnostics for `not_v3_envelope`, `invalid_envelope`, `group_mismatch`, `peer_mismatch`, `unknown_group`, `ambiguous_signing_key`, `ambiguous_transport_peer`, `non_member`, `unbound_device`, `unauthorized_writer`, `missing_key`, and `bad_signature_or_epoch`. For each reason it asserts exactly one log and one `group:validation_rejected` event, verifies the event key set is only `reason`, `groupHash`, `senderHash`, `transportPeerHash`, `localPeerHash`, `envelopeType`, and `keyEpoch`, checks every hash equals the expected 12-character truncated hash or `none`, and proves logs/events omit raw group IDs, sender IDs, transport/local peer IDs, message IDs, device IDs, key-package IDs, public keys, signatures, ciphertext, nonce, and plaintext markers.

Validation passed:

- `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go`
- `cd go-mknoon && go test ./node -run 'TestGA026' -count=1` (`ok node 0.541s`)
- `cd go-mknoon && go test ./node -run 'TestGA026|GroupTopicValidator|Device|TransportPeer|Authorization' -count=1` (`ok node 54.626s`)
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGA026|GroupTopicValidator|Device|TransportPeer|Authorization|ValidationReject' -count=1` (`ok node 54.930s`, `ok internal 0.366s [no tests to run]`, `ok crypto 0.975s [no tests to run]`)
- `cd go-mknoon && go test -race ./node -run 'TestGA026|ValidationReject' -count=1` (`ok node 1.643s`)
- `./scripts/run_test_gates.sh groups` (`+159`)
- `git diff --check -- go-mknoon/node/pubsub_authorization_forward_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GA-026-plan.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Final Verdict

Accepted/closed. GA-026 is `Covered` with exact native all-reject-reason diagnostic privacy evidence, no production runtime change was required beyond existing hashed diagnostic behavior, and no row-owned residual remains. Continue from GI-034, the next unresolved session in ordered ledger order; do not write a final program verdict while later rows remain unresolved.
