# GL-016 GetGroupKeyInfo Clone Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 22:57 CEST - Local gap-closure pass reached GL-016 after GL-010 closure. Files inspected: source matrix GL-016 row, session-breakdown GL-016 row, existing `GetGroupKeyInfo` tests, `go-mknoon/node/pubsub.go::GetGroupKeyInfo`, `cloneGroupKeyInfo`, and adjacent publish/update-key tests. Decision: keep GL-016 as `needs_tests_only`; current code already returns through `cloneGroupKeyInfo`, but the source row was `Open`, no adjacent GL-016 plan existed, and no exact row-owned test mutated the returned struct and then proved internal key state plus publish behavior remained intact.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GL-016 | GetGroupKeyInfo returns a clone and cannot mutate internal state | G is joined with key info. | 1. Call GetGroupKeyInfo. 2. Mutate returned struct. 3. Call again and publish/decrypt. | Internal key state is unchanged. | P1 | Open | Required | Recommended | N/A | N/A | N/A | cloneGroupKeyInfo at pubsub.go:396-402. |

## Reconciliation Verdict

GL-016 was repo-owned because the row targets native key-info access behavior in this repository. The blocker was missing exact proof, not missing product design or external fixture. Existing tests proved basic current-key and nil-unknown behavior, and GL-005 proved the returned pointer was not the internal stored key immediately after join, but no exact GL-016 proof mutated every returned field after a key rotation and verified internal state plus publishability.

## Scope

Own exactly GL-016:

- Add an exact Go regression that joins a group with a generated valid key, rotates to a second generated valid key, retrieves key info, mutates every returned field, and retrieves again.
- Prove current key, current epoch, previous key, previous epoch, and grace deadline are unchanged internally.
- Prove `GetGroupKeyInfo` returns a fresh pointer.
- Prove publish still succeeds after the caller corrupts the returned clone.
- Update the source matrix, breakdown ledgers, and test inventory with concrete evidence.

## Out Of Scope

- Changing `cloneGroupKeyInfo`, because current shallow struct cloning is sufficient for string/time fields.
- Key-epoch grace behavior, which is covered by GL-014, GL-015, and GK rows.
- Flutter bridge key serialization, because GL-016 3-Party E2E is N/A and no Dart-facing code changed.

## Owner Files

- `go-mknoon/node/pubsub_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-016-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/pubsub_test.go
cd go-mknoon && go test ./node -run 'TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState' -count=1
cd go-mknoon && go test ./node -run 'GetGroupKeyInfo|JoinGroupTopic|UpdateGroupKey|PublishGroupMessage' -count=1
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-016-plan.md
```

## Done Criteria

- Source row GL-016 is `Covered` with concrete file/test/gate evidence.
- Exact row-owned Go proof exists and passes.
- The returned `GroupKeyInfo` clone can be mutated without changing internal current/previous key state.
- Publish remains successful after clone mutation.
- No `accepted_with_explicit_follow_up` is used for unresolved GL-016 gaps.

## Execution Evidence

- Exact test:
  - `go-mknoon/node/pubsub_test.go::TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState` starts a real local node, joins `gl016-cloned-key-info` with a generated epoch-1 key, rotates to a generated epoch-2 key, retrieves key info, and verifies current epoch/key plus previous epoch/key and a non-zero grace deadline.
  - The test mutates the returned clone's `Key`, `KeyEpoch`, `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline`, then retrieves key info again and proves the internal values are unchanged and the returned pointer is fresh.
  - The test publishes `gl016-clone-message` after clone mutation and expects success with `peerCount == 0`, which proves the internal current key was not corrupted by caller mutation.
- Validation evidence:
  - `gofmt -w go-mknoon/node/pubsub_test.go` passed.
  - `cd go-mknoon && go test ./node -run 'TestGL016GetGroupKeyInfoReturnsCloneCannotMutateInternalState' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 0.786s`).
  - `cd go-mknoon && go test ./node -run 'GetGroupKeyInfo|JoinGroupTopic|UpdateGroupKey|PublishGroupMessage' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 3.554s`).
  - `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed (`+5 All tests passed`).
  - `./scripts/run_test_gates.sh groups` passed (`+159 All tests passed`).

## Final Verdict

GL-016 is accepted/closed. The source matrix row is `Covered` with exact clone-mutation proof, adjacent native key/join/publish proof, Flutter startup rejoin smoke, named groups gate, and diff hygiene. Residual-only: none. Continue from GL-020, the next unresolved session in ordered ledger order.
