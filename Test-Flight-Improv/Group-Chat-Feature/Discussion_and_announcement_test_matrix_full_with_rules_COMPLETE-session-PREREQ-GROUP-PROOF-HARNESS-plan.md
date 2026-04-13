# Session Plan: PREREQ-GROUP-PROOF-HARNESS

## Session Contract

- source row: `shared prerequisite for RC-009, SV-004, SV-005, SV-006, and SV-007`
- session classification: `implementation-ready`
- closure target for this session: add reusable proof helpers that later row-owned sessions can call directly for raw group-envelope mutation, event capture, previous-key grace, and rotation-race setup, then update the breakdown and inventory to cite that shared harness without overclaiming any dependent row as closed

## Real Scope

- add or tighten shared Go test helpers for:
  - building deterministic group-message envelopes
  - mutating ciphertext / nonce / key-epoch inputs without hand-copying envelope wiring
  - publishing raw envelopes into joined local nodes and collecting emitted Go events
  - setting up previous-key grace and concurrent rotation fixtures that later row-owned sessions can reuse
- add the smallest direct proof that the new helpers are reusable from the existing group pubsub test files
- do not close `RC-009`, `SV-004`, `SV-005`, `SV-006`, or `SV-007` in this session

## Source Of Truth

- current breakdown artifact:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- source matrix:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- existing Go proof surfaces:
  `go-mknoon/node/pubsub_test.go`
  `go-mknoon/node/pubsub_decryption_failure_test.go`
  `go-mknoon/node/pubsub_key_rotation_grace_test.go`
  `go-mknoon/node/pubsub_delivery_test.go`
  `go-mknoon/node/node_test.go`
- inventory doc:
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Exact Problem Statement

- the repo already has isolated validator and delivery tests, but the remaining security rows still depend on ad hoc envelope construction and event capture spread across multiple files
- without one shared harness, later row sessions would keep duplicating setup for tampered ciphertext, wrong-key / wrong-nonce, replay or reorder injection, and key-rotation fixtures
- this prerequisite must land that reusable proof seam first so later row sessions can stay narrow and row-owned

## Files And Repos To Inspect Next

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/node_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/bridge/bridge.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

## Existing Tests Covering This Area

- `pubsub_test.go` already exposes `buildTestEnvelope(...)` and `validateGroupEnvelope(...)`
- `pubsub_decryption_failure_test.go` already proves `group:decryption_failed` and `group:payload_parse_failed` are emitted and no `group_message:received` slips through
- `pubsub_key_rotation_grace_test.go` already proves previous-key grace acceptance and real subscription decrypt during grace
- `pubsub_delivery_test.go` and `node_test.go` already provide local-node and event-collector fixtures

## Regression / Tests To Add First

1. extract or add shared helper coverage in `go-mknoon/node/*test.go` so tampered envelope and event-capture scenarios stop being file-local
2. add at least one direct helper-driven proof in the decryption-failure / key-rotation area so later row sessions can reuse the same seam instead of re-deriving it

## Step-By-Step Implementation Plan

1. inspect the existing envelope builder, event collector, and local multi-node helpers
2. add a shared Go test helper file for raw group-envelope mutation and event-driven publish assertions
3. switch the current decryption-failure and grace tests to the shared helper where that reduces duplication without widening behavior
4. run the targeted Go tests to prove the harness is stable
5. update the inventory and breakdown to mark the prerequisite accepted while keeping dependent rows open

## Risks And Edge Cases

- do not accidentally change production pubsub logic while refactoring tests
- keep helper behavior deterministic so future replay / race tests stay stable
- avoid letting the prerequisite doc wording imply any dependent row is now covered

## Exact Tests And Gates To Run

- `cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_(EmitsDecryptionFailedEvent|EmitsPayloadParseFailedEvent|DecryptsPreviousEpochDuringGrace)|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)'`
- named gates for this prerequisite: `Unit (Required)`, `Integration (Required)` via Go node-local subscription tests

## Known-Failure Interpretation

- if unrelated pre-existing Flutter failures appear outside the targeted Go test command, they do not block this prerequisite
- if the targeted Go command fails in the touched pubsub test files, treat that as a real blocker for this session

## Done Criteria

- one reusable shared proof helper surface exists on disk for raw envelope mutation / publish / event capture or key-rotation setup
- the touched decryption / grace tests pass through that shared surface
- the breakdown and inventory cite the shared prerequisite truth without closing dependent rows

## Scope Guard

- do not implement row-owned fixes for `RC-009`, `SV-004`, `SV-005`, `SV-006`, or `SV-007` here
- do not add dispatcher-overflow work in this session
- do not widen into encrypted offline replay or relay storage changes

## Accepted Differences / Intentionally Out Of Scope

- no real-device or multi-process proof in this prerequisite
- no Dart-side diagnostic routing contract changes yet unless a minimal seam is required to keep the helper story coherent

## Dependency Impact

- unblocks later row-owned sessions `RC-009`, `SV-004`, `SV-005`, `SV-006`, and `SV-007`
- does not change the blocked state of `PREREQ-GROUP-OFFLINE-REPLAY`
