# Private Group Chat Reliability Matrix - Session GA-018 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-14 00:09 CEST - Local gap-closure pass reached GA-018 after GK-032 closure. Source matrix row GA-018 is `Open`; session ledger row 193 is `implementation-ready` / `needs_code_and_tests`; no adjacent GA-018 plan existed. Inspected the source row, session ledger, `go-mknoon/node/pubsub.go::groupEnvelopeOriginatesFromLocalTransport`, `handleGroupSubscription`, and the adjacent GA-017 sibling-device self-skip proof.
- 2026-05-14 00:18 CEST - Implemented and validated the exact row-owned same-transport self-echo proof. Source matrix row GA-018 is now `Covered`; session ledger row 193 is now `covered/accepted`.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GA-018 | Self echo from same transport is skipped once | Covered | covered/accepted |

## Gap Classification

`needs_code_and_tests`.

Current production code already skips only envelopes whose explicit `senderTransportPeerId` matches the local peer id, falling back to `senderId` only for legacy envelopes. GA-017 proves sibling-device traffic is not skipped, but GA-018 still lacks exact proof that a same-transport local echo reaching the subscription path emits no duplicate incoming message while the local publish/debug event remains separate.

## Scope

Owned files:

- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Dart/Flutter role or authorization files unless the Go exact proof exposes a product behavior gap.
- Device-lab or relay-backed harness changes; the row is host-native and has 3-Party E2E marked N/A.

## Implementation Plan

1. Add an exact Go regression that first proves the raw subscription path can deliver a non-local control envelope to the local node.
2. Publish or inject a valid same-transport local echo envelope with the local peer id in `senderTransportPeerId`.
3. Assert the local sender still has its separate `group:publish_debug` event, and no duplicate `group_message:received`, decrypt, payload-parse, or validation side effect is emitted for the self echo.
4. Run focused GA-018 tests, adjacent GA-017/transport/device selectors, selected race proof, gofmt, named groups gate, and diff hygiene.
5. Update the source matrix, breakdown ledger, plan verdict, and test inventory with concrete evidence before accepting the row.

## Acceptance Bar

- Source matrix row GA-018 is `Covered`.
- Session ledger row 193 is `covered/accepted`.
- Tests include an exact `GA-018` selector for same-transport self-echo skip behavior.
- Evidence records focused selector, adjacent Go gates, selected race proof, named groups gate, and `git diff --check`.
- Residual-only entry is `none`; no unresolved row-owned blocker remains.

## Execution Evidence

Implemented `go-mknoon/node/pubsub_delivery_test.go::TestGA018SameTransportSelfEchoIsSkippedOnce`. The test creates a real two-node private group, proves local `PublishGroupMessage` emits a separate `group:publish_debug` event for the explicit message id, proves a non-local raw control envelope reaches the local subscription and emits `group_message:received`, then raw-publishes a valid same-transport self-echo envelope with the local peer id in `senderTransportPeerId`. The self echo is classified as local transport and emits no duplicate `group_message:received`, no decrypt failure, no payload parse failure, and no validation rejection.

Validation passed:

- `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
- `cd go-mknoon && go test ./node -run 'TestGA018' -count=1` (`ok node 4.714s`)
- `cd go-mknoon && go test ./node -run 'TestGA017|TestGA018|TransportPeer|Device|Authorization|SelfEcho' -count=1` (`ok node 55.671s`)
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGA017|TestGA018|GroupTopicValidator|Device|TransportPeer|Authorization|GroupMessage' -count=1` (`ok node 60.677s`, `ok internal 1.280s`, `ok crypto 1.024s`)
- `cd go-mknoon && go test -race ./node -run 'TestGA017|TestGA018|TransportPeer|Device|PublishGroupMessage' -count=1` (`ok node 59.023s`)
- `./scripts/run_test_gates.sh groups` (`+159`)
- `git diff --check -- go-mknoon/node/pubsub_delivery_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GA-018-plan.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Final Verdict

Accepted/closed. GA-018 is `Covered` with exact live Go subscription-path evidence, no additional production runtime change was required beyond the existing transport-aware helper, and no row-owned residual remains. Continue from GP-007, the next unresolved session in ordered ledger order; do not write a final program verdict while later rows remain unresolved.
