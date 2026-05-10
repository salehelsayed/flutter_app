# GL-014 UpdateGroupKey Older Epoch Plan

Status: execution-ready

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Row: `GL-014 | UpdateGroupKey ignores older epoch without losing current key | G has current epoch 3. | 1. UpdateGroupKey with epoch 2. 2. Publish/decrypt epoch 3. 3. Inspect GetGroupKeyInfo. | Epoch 3 remains current and no previous-key window is replaced by stale data. | P0 | Open | Required | Required | N/A | N/A | N/A | pubsub.go:376-377.`

## Planning Progress

- `2026-05-10 06:49:22 CEST` - Arbiter completed. Files inspected since last update: reviewer notes, arbiter classifications, final plan sections. Decision/blocker: no structural blockers remain; final status set to `execution-ready` for a later implementation session. Next action: stop planning and report final verdict.
- `2026-05-10 06:49:22 CEST` - Reviewer completed / Arbiter started. Files inspected since last update: full GL-014 draft plan. Decision/blocker: plan is sufficient as written; no missing mandatory section, no stale source-of-truth issue, and no unsafe production/Dart scope expansion found. Next action: arbitrate reviewer findings and finalize readiness.
- `2026-05-10 06:47:03 CEST` - Reviewer started. Files inspected since last update: GL-014 draft plan sections. Decision/blocker: review will check whether tests-only classification, regression shape, gate contract, and GL-015 separation are sufficient. Next action: review for missing files/tests/gates, stale assumptions, overengineering, and minimum adjustments.
- `2026-05-10 06:47:03 CEST` - Planner completed. Files inspected since last update: no new files; draft synthesized from evidence. Decision/blocker: smallest coherent plan is tests-only unless the new row-owned regression fails; no Dart/Flutter production edits are planned. Next action: run Reviewer against the draft.
- `2026-05-10 06:47:03 CEST` - Planner started. Files inspected since last update: no new files; planning from collected GL-014 evidence and focused current-test result. Decision/blocker: current production appears to ignore stale epochs, but current dirty-tree test is insufficient for the exact row because it does not cover epoch 3 or publish/decrypt. Next action: draft a tests-only regression-first plan with production edits only if the row-owned test fails.

## Execution Progress

- `2026-05-10 06:51:58 CEST` - Contract extracted / Executor started. Files inspected since last update: GL-014 plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go`, local node/event helper definitions. Decision/blocker: no sub-agent tool is available, so the `implementation-execution-qa-orchestrator` local sequential fallback is being used; scope remains tests-only unless the row-owned regression exposes a production defect. Next action: add the GL-014 regression in the row-owned Go test file.
- `2026-05-10 06:53:06 CEST` - Executor progress. Files touched since last update: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Decision/blocker: added `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` and ran `gofmt`; no production files touched. Next action: run the focused GL-014 command for RED/GREEN evidence.
- `2026-05-10 06:53:39 CEST` - Focused RED/GREEN evidence. Command finished: `(cd go-mknoon && go test ./node -run '^TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery$|^TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent$' -count=1)`. Result: PASS (`ok github.com/mknoon/go-mknoon/node 1.207s`). Decision/blocker: the new regression passed immediately, so no production GL-014 defect was exposed and `go-mknoon/node/pubsub.go` remains untouched. Next action: run the required race proof.
- `2026-05-10 06:54:37 CEST` - Go gate evidence. Commands finished: `(cd go-mknoon && go test -race ./node -run '^TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery$' -count=1)` PASS (`ok github.com/mknoon/go-mknoon/node 2.112s`); `(cd go-mknoon && go test ./node -run 'UpdateGroupKey|HandleGroupSubscription_DecryptsPreviousEpoch|HandleGroupSubscription_DropsPreviousEpoch|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_AcceptsPreviousEpochDuringGrace' -count=1)` PASS (`ok github.com/mknoon/go-mknoon/node 2.462s`); `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` PASS (`ok github.com/mknoon/go-mknoon/node 17.163s`). Decision/blocker: required Go focused, race, adjacent, and row sweeps are green. Next action: run Flutter startup rejoin smoke.
- `2026-05-10 06:55:26 CEST` - Flutter/diff evidence. Commands finished: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` PASS (`00:00 +3: All tests passed!`); `git diff --check` PASS (no output). Decision/blocker: all required non-conditional commands are green; `./scripts/run_test_gates.sh groups` is not required because no production behavior changed. Next action: perform local QA Reviewer pass against the diff and plan.
- `2026-05-10 06:56:14 CEST` - QA Reviewer completed / final verdict. Files inspected since last update: GL-014 test diff, GL-014 execution progress, `go-mknoon/node/pubsub.go` dirty diff for scope awareness. Decision/blocker: accepted; no blocking issues found. The row-owned regression proves epoch-3 current/previous key preservation after stale epoch-2 update and successful epoch-3 publish/decrypt with no receiver decryption failure. No GL-014 production code changed; existing broader dirty work was preserved. Next action: hand off to closure phase; do not edit source matrix or session breakdown here.
- `2026-05-10 06:56:45 CEST` - Final hygiene rerun. Command finished after the final plan update: `git diff --check` PASS (no output). Decision/blocker: no whitespace blockers in tracked diffs. Next action: final response.

## Evidence Collector Notes

- Source matrix row GL-014 is P0/Open and requires this exact sequence: group current epoch 3, `UpdateGroupKey` with older epoch 2, publish/decrypt epoch 3, inspect `GetGroupKeyInfo`; expected result is epoch 3 remains current and the previous-key grace window is not replaced by stale data.
- Breakdown row GL-014 is still open, classified as `needs_code_and_tests` / `implementation-ready`, and names `go-mknoon/node/pubsub.go`, Go pubsub tests, and `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` as relevant evidence/gates.
- Current `go-mknoon/node/pubsub.go::UpdateGroupKey` stores the first key, returns without mutation when `keyInfo.KeyEpoch <= current.KeyEpoch`, and only creates a previous-key grace window on a strictly newer epoch.
- Current `GetGroupKeyInfo` returns a cloned `GroupKeyInfo`, so tests can inspect current key, previous key, previous epoch, and grace deadline without mutating node state.
- Dirty tree already contains `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent`; it joins with epoch 1, updates to epoch 2, applies stale epoch 1, and verifies current key/epoch, previous key/epoch, and grace deadline are unchanged.
- Focused verification of that existing dirty-tree test passed: `(cd go-mknoon && go test ./node -run '^TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent$' -count=1)`.
- The existing dirty-tree older-epoch test is not sufficient for GL-014 closure because it does not establish current epoch 3, does not use real generated group keys, and does not prove post-stale-update publish/decrypt of an epoch-3 message.
- Existing key-rotation grace tests already cover previous-epoch decrypt during grace and rejection after grace expiry. GL-014 should preserve those and keep GL-015 same-epoch mismatch policy separate.
- `PublishGroupMessage` uses the sender node's current `GroupKeyInfo` key and epoch for encryption/signing. `handleGroupSubscription` decrypts using the receiver node's current/previous key info and emits `group_message:received` on successful decrypt.
- Local two-node helpers already exist: `startLocalNodeForMultiRelayTest`, `startLocalNodeForMultiRelayTestWithCollector`, `connectLocalGroupNodes`, `waitForGroupTopicPeerCount`, `waitForCollectedEvent`, and real `mcrypto.GenerateGroupKey`.
- `Test-Flight-Improv/test-gate-definitions.md` defines `./scripts/run_test_gates.sh groups` for group send, receive, retry, resume, invite, or announcement behavior changes. For a tests-only GL-014 proof that does not change production behavior, the named groups gate is conditional rather than mandatory.

## real scope

GL-014 owns only the older-epoch key-update contract:

- prove that a group with current epoch 3 ignores an `UpdateGroupKey` call carrying older epoch 2;
- prove the current epoch-3 key remains usable for real `PublishGroupMessage` encryption and receiver-side `handleGroupSubscription` decryption after the stale update;
- prove `GetGroupKeyInfo` still reports epoch 3 as current and preserves the pre-existing previous-key grace window instead of replacing it with stale epoch-2 material;
- add the smallest row-owned Go regression in `go-mknoon/node/pubsub_key_rotation_grace_test.go`;
- edit `go-mknoon/node/pubsub.go::UpdateGroupKey` only if the new regression fails and identifies a real stale-epoch mutation bug.

Do not edit Dart/Flutter production code, Go bridge APIs, source matrix, session breakdown, test-gate docs, GL-013 tests, GL-015 same-epoch mismatch behavior, key distribution, invite/rejoin flows, or closure rows in this planning/execution scope.

## closure bar

GL-014 is good enough when a row-owned test demonstrates all of the following in the current architecture:

- sender and receiver are joined with a real generated epoch-2 group key, then both advance to a real generated epoch-3 group key;
- before stale update, `GetGroupKeyInfo` reports `KeyEpoch == 3`, `Key == epoch3Key`, `PrevKeyEpoch == 2`, `PrevKey == epoch2Key`, and a non-zero grace deadline;
- after `UpdateGroupKey(groupId, &GroupKeyInfo{Key: staleEpoch2Key, KeyEpoch: 2})`, `GetGroupKeyInfo` remains byte-for-byte equivalent for current key, previous key, previous epoch, and grace deadline;
- `PublishGroupMessage` after the stale update succeeds from the sender and uses the still-current epoch-3 key;
- the receiver emits `group_message:received` with the expected group, sender, message id/text, and does not emit `group:decryption_failed`;
- the same focused test passes under normal Go test and race detector, with adjacent key-rotation/grace tests still green;
- no production files are edited if the new row-owned regression passes on current code.

## source of truth

Authoritative sources, in order:

1. Current Go code/tests in `go-mknoon/node`, especially `pubsub.go`, `pubsub_key_rotation_grace_test.go`, `pubsub_delivery_test.go`, `group_security_harness_test.go`, and `pubsub_test.go`.
2. `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` for named gates; if they disagree, the script wins.
3. Source matrix row GL-014 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
4. Breakdown row GL-014 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

Current code and executable tests beat stale prose. GL-013 nil-key removal and GL-015 same-epoch mismatch are separate row contracts.

## session classification

`implementation-ready`

Row disposition: tests-only regression-first unless the row-owned regression fails. This is not `stale/already-covered` because current dirty-tree coverage does not prove epoch-3 publish/decrypt under the exact source row conditions.

## exact problem statement

Known production code appears to have the intended stale-epoch guard: `UpdateGroupKey` returns when `keyInfo.KeyEpoch <= current.KeyEpoch`. The remaining GL-014 gap is coverage precision, not a confirmed production defect.

The source row requires more than inspecting local key info after a stale update. It requires current epoch 3, a stale epoch-2 update, a successful publish/decrypt at epoch 3 afterward, and `GetGroupKeyInfo` proof that stale data did not replace the previous-key window. The current dirty-tree test proves a simpler epoch-2/epoch-1 local-state case, so GL-014 needs an explicit row-owned regression.

User-visible behavior to protect: delayed or replayed older group key updates must not knock a device back to stale key material or break current group message delivery.

Must stay unchanged: valid forward rotation still establishes a previous-key grace window, previous-epoch decrypt during grace still works, expired previous-epoch traffic is rejected, nil-key removal from GL-013 stays separate, and same-epoch mismatched material from GL-015 is not redefined here.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh` only if a named gate command behaves differently than the doc describes

Do not inspect or edit Dart/Flutter production files unless the Go regression unexpectedly points to an app-layer contract issue.

## existing tests covering this area

- `TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline` proves a strictly newer key update stores the previous key and grace deadline.
- `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` exists in the dirty tree and passes; it proves a local stale epoch-1 update does not mutate an epoch-2 current key, previous key, or grace deadline.
- `TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial` exists in the dirty tree and is GL-015-adjacent; preserve it but do not use it to close GL-014.
- `TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace`, `TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace`, `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace`, and `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires` pin current/previous epoch validation and delivery behavior around grace windows.
- `pubsub_delivery_test.go` already has two-node `PublishGroupMessage` delivery patterns with collectors, peer-count waiting, message id assertions, and received-event checks.

Missing: a GL-014-named or GL-014-owned regression that combines current epoch 3, stale epoch 2, real generated group keys, actual post-stale-update publish/decrypt, and `GetGroupKeyInfo` inspection after delivery.

## regression/tests to add first

Add one narrow Go test before any production edit:

`go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery`

Test shape:

1. Generate sender Ed25519 keys and receiver public key material using existing helpers.
2. Generate three real group keys with `mcrypto.GenerateGroupKey`: `epoch2Key`, `epoch3Key`, and `staleEpoch2Key`.
3. Start two local nodes: sender `nodeA` and receiver `nodeB` with a `testEventCollector`.
4. Build a chat `GroupConfig` with `nodeA` as an admin/writer and `nodeB` as a member.
5. Join both nodes at epoch 2 with `epoch2Key`.
6. Advance both nodes to epoch 3 with `epoch3Key` through `UpdateGroupKey`.
7. Capture `beforeA := nodeA.GetGroupKeyInfo(groupId)` and `beforeB := nodeB.GetGroupKeyInfo(groupId)`; assert both current/previous fields match epoch 3/epoch 2 and grace deadline is non-zero.
8. Apply stale epoch-2 update to both nodes with `staleEpoch2Key`.
9. Reinspect both nodes with `GetGroupKeyInfo`; assert current key/epoch, previous key/epoch, and `GraceDeadline` still equal the before snapshots.
10. Connect nodes, wait for topic peer count, then call `nodeA.PublishGroupMessage` with a fixed GL-014 message id and text.
11. Assert publish succeeds with a non-empty/fixed message id and `peerCount >= 1`.
12. Wait for `nodeB` to emit `group_message:received`; assert `groupId`, `senderId`, `messageId`, and `text`.
13. Assert no `group:decryption_failed` appears in receiver events after the publish baseline.
14. Reinspect `nodeB.GetGroupKeyInfo` one more time to prove delivery did not mask a stale key-info mutation.

Expected result on current code: GREEN. If this is RED, treat it as a real GL-014 production defect and patch only the stale-epoch path in `UpdateGroupKey` or the exact delivery seam the failure identifies.

## step-by-step implementation plan

1. Recheck `git status --short` and relevant diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/pubsub_decryption_failure_test.go`; preserve unrelated dirty changes, especially GL-013 and GL-015 tests.
2. Add `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` in `go-mknoon/node/pubsub_key_rotation_grace_test.go` near the existing `UpdateGroupKey` rotation tests.
3. Reuse existing helpers instead of adding a new harness: `generateEd25519KeyPair`, `mcrypto.GenerateGroupKey`, `startLocalNodeForMultiRelayTest`, `startLocalNodeForMultiRelayTestWithCollector`, `connectLocalGroupNodes`, `waitForGroupTopicPeerCount`, and `waitForCollectedEvent`.
4. Keep the test self-contained and GL-014-specific. Do not alter `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent`, `TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial`, or GL-013 tests except for unavoidable imports/gofmt caused by the new test.
5. Run the focused GL-014 command. If the new test passes, make no production code edits.
6. If the focused test fails because stale epoch 2 mutates epoch 3 state, patch only `go-mknoon/node/pubsub.go::UpdateGroupKey` so older epochs return without changing current/previous key info. Preserve nil update behavior and same-epoch policy.
7. If the focused test fails because publish/decrypt fails despite correct key info, inspect only the narrow delivery/validation path involved before editing. Do not broaden into Flutter or bridge work without concrete failing evidence.
8. Run the required focused, race, adjacent, row, Flutter smoke, conditional groups gate, and diff-check commands below.
9. Stop after implementation evidence. Do not update the source matrix, session breakdown, closure docs, or row status in this session.

## risks and edge cases

- Applying stale epoch 2 only to the receiver would prove decrypt but not the sender publish path; the planned regression applies it to both nodes.
- A direct join at epoch 3 would not prove the previous-key window preservation. The planned regression joins at epoch 2 and advances to epoch 3 first.
- The stale update must use a different real generated epoch-2 key to catch accidental previous-key replacement.
- `GraceDeadline.Equal(before.GraceDeadline)` is intentional because a stale update should not reset the grace window.
- Pubsub delivery tests can be timing-sensitive; use existing local-node peer-count and event-wait helpers instead of fixed sleeps beyond existing helper behavior.
- Event assertions should inspect only events after the publish baseline so prior setup/debug events do not confuse the no-decryption-failure assertion.
- Race detector coverage is useful because the test uses local pubsub handlers and shared node state, even though the stale update itself is applied before publish.
- GL-015 same-epoch mismatch must stay separate; do not add same-epoch stale material assertions to the GL-014 test.

## exact tests and gates to run

Focused GL-014 proof:

```bash
(cd go-mknoon && go test ./node -run '^TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery$|^TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent$' -count=1)
```

Focused race proof because the row-owned regression uses local pubsub delivery and handler goroutines:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery$' -count=1)
```

Adjacent key-rotation and grace delivery sweep:

```bash
(cd go-mknoon && go test ./node -run 'UpdateGroupKey|HandleGroupSubscription_DecryptsPreviousEpoch|HandleGroupSubscription_DropsPreviousEpoch|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_AcceptsPreviousEpochDuringGrace' -count=1)
```

Row Go sweep from the breakdown:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Flutter startup rejoin smoke listed by the GL row/breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named groups gate only if production behavior changes or the focused regression fails and requires a source edit:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

No Dart/Flutter broad sweep, completeness check, simulator, or group-real-network-nightly command is planned unless implementation edits gate definitions, Dart/Flutter code, or production group delivery behavior.

## known-failure interpretation

- A failure of the new focused GL-014 test before production edits is blocking for GL-014 and must be classified by exact failing assertion: stale key-info mutation, publish failure, decrypt failure, or unexpected diagnostic.
- If existing `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` fails, treat that as an adjacent stale-epoch regression and do not proceed until the local-state contract is understood.
- Race detector failures are blocking if they involve `UpdateGroupKey`, `GetGroupKeyInfo`, pubsub delivery, collector access, or group key/config maps.
- Broad Flutter or named gate failures are GL-014 blockers only if they involve group startup rejoin, group send/receive, key rotation, or code touched by this execution. Unrelated dirty-tree failures should be recorded exactly and not hidden by narrowing gates.
- Do not remove, skip, or weaken GL-013, GL-015, grace-window, or delivery tests to make GL-014 green.

## done criteria

- The GL-014 plan remains file-backed and execution evidence can be recorded later without changing source matrix or breakdown status during planning.
- `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` exists and proves current epoch 3, stale epoch 2, real generated keys, publish/decrypt epoch 3, and `GetGroupKeyInfo` preservation.
- Existing `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` remains present and passing.
- GL-013 and GL-015 dirty-tree tests are preserved.
- No production code is edited if the new row-owned regression passes on current code.
- If production code is edited due to a RED, the edit is limited to the failed GL-014 stale-epoch seam and all required gates above are run.
- `git diff --check` passes.
- Source matrix row GL-014 and the session breakdown are not closed or edited in this planning/execution plan.

## scope guard

Non-goals:

- no Dart/Flutter production edits;
- no bridge API edits;
- no source matrix, breakdown, closure, or test-gate-definition edits;
- no changes to GL-013 nil-key behavior;
- no changes to GL-015 same-epoch mismatch policy;
- no changes to previous-key grace period length or expiry rules;
- no key distribution, invite, rejoin, pending-repair, relay, or multi-device feature work;
- no generalized key-state machine or new exported API.

Overengineering would include adding a new test harness when existing local node helpers cover the row, adding app-layer tests for a Go-only stale-epoch guard, or folding same-epoch/future-epoch policy into GL-014.

## accepted differences / intentionally out of scope

- The existing dirty-tree `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` remains useful adjacent evidence but is intentionally not treated as complete GL-014 closure.
- The planned GL-014 test may pass without production edits; that is an acceptable tests-only outcome because current code already appears to implement the stale-epoch guard.
- The named groups gate is conditional for tests-only execution because no shipped behavior changes if the new regression passes. If production code changes, the groups gate becomes required.
- GL-015 same-epoch mismatched material remains a separate policy row even though `UpdateGroupKey` currently handles same and older epochs with the same early return condition.

## dependency impact

- GL-015 can rely on GL-014 not redefining same-epoch mismatch semantics.
- Later GL-019 concurrent join/leave/update stress can include stale-epoch updates after GL-014 lands, but should not duplicate this row's deterministic publish/decrypt proof.
- Group key repair and rejoin rows can rely on delayed older direct key updates not downgrading current local key state once this row has a passing row-owned regression.

## Reviewer Notes

Reviewer verdict: sufficient as-is.

Sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None for planning. The exact row-owned Go regression, focused/race/adjacent/row commands, Flutter startup smoke, conditional groups gate, and diff check are listed.
- What assumptions are stale or incorrect? None found. The plan correctly treats source matrix/breakdown as open while recognizing current code and the dirty-tree local-state test as partial evidence only.
- What is overengineered? Nothing material. A single two-node Go regression reuses existing helpers and avoids new harnesses, Dart edits, bridge work, and closure-doc churn.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. The implementation steps name the test location, helper reuse, exact key epochs/material, required assertions, and the stop rule if the test passes.
- What is the minimum needed to make the plan sufficient? Already present: add the GL-014 row-owned regression first; edit production only if that regression fails; run the listed gates.

Reviewer cautions for execution:

- Keep the test name GL-014-specific so it is unambiguous row evidence.
- Apply the stale epoch-2 update to both sender and receiver so publish and decrypt are both covered.
- Keep same-epoch mismatch assertions out of this test; GL-015 remains separate.
- Run the named groups gate only if production behavior changes, as the plan states.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- Exact helper variable names and assertion ordering can be chosen during implementation as long as the test proves epoch 3 current state, stale epoch 2 ignored state, publish/decrypt success, and no decryption failure.
- The implementation session may include the already-passing `TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent` in the focused command as adjacent evidence, but the new GL-014 test is the closure proof.

Accepted differences intentionally left unchanged:

- GL-014 is classified `implementation-ready` with a tests-only row disposition, not `stale/already-covered`, because existing coverage is partial.
- No Dart/Flutter production work is planned; the only Flutter command is the startup rejoin smoke listed by the GL row/breakdown.
- The source matrix and session breakdown remain open and untouched; closure is a later phase.

Final arbiter verdict: execution-ready. The plan is safe to implement now because it is narrow, evidence-backed, regression-first, preserves unrelated dirty work, has a clear stop rule, and contains exact direct commands/gates.
