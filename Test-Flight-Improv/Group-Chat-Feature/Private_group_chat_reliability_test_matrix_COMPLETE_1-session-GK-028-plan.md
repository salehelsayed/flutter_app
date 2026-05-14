# Private Group Chat Reliability Matrix - Session GK-028 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 23:32 CEST - Local gap-closure pass reached GK-028 after GM-032 closure. Source matrix row GK-028 was `Open`; session ledger row 190 was `implementation-ready` / `needs_code_and_tests`; no adjacent GK-028 plan existed. Inspected the source row, session ledger, `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, `lib/features/groups/application/group_offline_replay_envelope.dart`, existing GK-026/GK-027 validator/live tests, and offline replay envelope tests.
- 2026-05-13 23:39 CEST - Added exact GK-028 pure Go validator, live raw-publish, and Dart offline replay regressions. Current production verifier already uses the configured member/device signing key, so closure is tests-only under the original `needs_code_and_tests` classification. Updated source matrix, breakdown, and test inventory evidence; GK-031 is next in ledger order.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GK-028 | Tampering SenderPublicKey does not bypass config public key | Covered | covered/accepted |

## Gap Classification

`needs_code_and_tests`.

Current validator behavior already appears to verify signatures with the configured active member/device signing key (`sourceDevice.DeviceSigningPublicKey`) rather than trusting the legacy envelope `senderPublicKey` field. The repo-owned gap is missing exact row evidence across the native validator/live raw-publish path and Dart offline replay verifier.

## Scope

Owned files:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Wire schema changes.
- Device-lab or relay-backed harness changes unless focused host proof exposes a missing runtime behavior.
- Broad key rotation or membership refactors outside the sender public-key tamper path.

## Implementation Plan

1. Add an exact pure Go validator regression proving an envelope claiming a configured member but signed with an attacker key and carrying attacker `senderPublicKey` is rejected under the configured member key.
2. Add an exact live raw-publish regression proving the same tamper is rejected by the receiving validator without rendering plaintext, attribution, decryption, or parse diagnostics.
3. Add an exact Dart offline replay regression proving a replay envelope whose legacy sender key and signed payload are changed to an attacker key is rejected before decrypting and cannot bypass the configured device key.
4. Run focused tests, adjacent GK selector gates, formatting, the named groups gate, and diff hygiene.
5. Update the source matrix, breakdown ledger, plan verdict, and test inventory with concrete file/test/gate evidence before accepting the row.

## Acceptance Bar

- Source matrix row GK-028 is `Covered`.
- Session ledger row 190 is `covered/accepted`.
- Tests include exact `GK-028` selectors for native validator/live raw publish and Dart offline replay.
- Evidence records focused selectors, adjacent gates, named `./scripts/run_test_gates.sh groups`, and `git diff --check`.
- Residual-only entry is `none`; no unresolved row-owned blocker remains.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGK028ValidateGroupEnvelopeRejectsSenderPublicKeyBypass`.
- Added `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK028SenderPublicKeyTamperLiveRawPublishRejectsWithoutPayload`.
- Added `test/features/groups/application/group_offline_replay_envelope_test.dart::GK-028 decode rejects senderPublicKey tamper before decrypt`.
- Validation passed: gofmt, Dart format, focused Go GK-028 (`ok node 4.071s`), focused Dart GK-028 (`+1`), full offline replay envelope suite (`+3`), scoped analyzer clean, adjacent Go selector (`ok node 22.222s`, `ok internal 0.275s`, `ok crypto 0.891s`), and named `./scripts/run_test_gates.sh groups` (`+159`).

## Final Verdict

Accepted/closed. GK-028 is `Covered` in the source matrix and `covered/accepted` in session ledger row 190. No production runtime change was required because the current native validator already uses configured-key verification and the Dart replay verifier rejects sender-key mismatch before decrypt; the new row-owned tests lock both contracts. Residual-only: none. Continue with GK-031.
