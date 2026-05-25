# Group Key Grace Churn Session GKGC-001 Plan

Status: closed

Closure verdict: closed
Execution result audited: accepted

## Planning Progress

- 2026-05-23 23:29:05 CEST - Reviewer started. Files inspected since last update: draft plan content in this file. Decision/blocker: checking sufficiency against mandatory sections, source evidence, and host-only scope. Next action: record reviewer findings.
- 2026-05-23: Controller local plan fallback finalized status after bounded child-planner no-progress. Reviewer intake showed no scope blocker, and the draft already contained scope, tests, gates, done criteria, scope guard, and host-only proof profile.
- 2026-05-23 23:28:40 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with regression-first tests, exact host-only gates, scope guard, and proof profile. Next action: Reviewer will check sufficiency and scope fit.
- 2026-05-23 23:25:55 CEST - Planner started. Files inspected since last update: none. Decision/blocker: draft will stay within node joined-key cloning plus bridge generate-next-key guard; no broader key-ring or Flutter/device work. Next action: write the execution-ready plan sections for review.
- 2026-05-23 23:25:35 CEST - Evidence Collector completed. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-key-grace-churn-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, `go-mknoon/bridge/bridge_test.go`. Decision/blocker: evidence supports one narrow implementation session; no blocker. Next action: Planner will draft the regression-first implementation plan.
- 2026-05-23 23:21:10 CEST - Evidence Collector started. Files inspected since last update: none. Decision/blocker: collecting only the breakdown artifact, direct Go files, direct tests, and gate definitions if present. Next action: inspect repo evidence for current key grace behavior and direct test coverage.

## Execution Progress

- 2026-05-23 23:27:16 CEST - Execution controller starting contract extraction. Files inspected or touched: skill file, this plan, `git status --short`. Command currently running: none. Decision/blocker: no child-agent spawn tool is available in this environment; using the skill's local sequential fallback within the exact write scope. Next action: extract the plan contract before RED tests.
- 2026-05-23 23:28:21 CEST - Contract extraction complete. Files inspected or touched: this plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`, scoped diffs. Command currently running: none. Decision/blocker: scope is limited to preserving incoming joined key grace metadata and rejecting `GroupGenerateNextKey` during active previous-key grace; required gates are the two exact Go commands. Next action: add RED regressions before implementation.
- 2026-05-23 23:28:55 CEST - RED test edit starting. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`. Command currently running: none. Decision/blocker: adding incoming-grace preservation regression and active-grace generate-next-key rejection coverage before product-code changes. Next action: run the two required Go commands for expected RED.
- 2026-05-23 23:30:27 CEST - RED test run starting. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`. Command currently running: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupKeyGraceChurn|TestGK017|TestGK018'`, then `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupGenerateNextKey'`. Decision/blocker: expecting the new/updated regressions to fail before product-code changes. Next action: record RED result and implement minimal code.
- 2026-05-23 23:31:08 CEST - RED test run complete; implementation starting. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`. Command currently running: none. Decision/blocker: expected RED observed: node test failed because joined key clone returned empty `PrevKey`/`PrevKeyEpoch`; bridge test failed because second generate returned `ok:true` instead of `GROUP_KEY_GRACE_ACTIVE`. Next action: update `joinedGroupKeyInfo` and add the bridge active-grace guard.
- 2026-05-23 23:31:41 CEST - Implementation complete; GREEN gate run starting. Files inspected or touched: `go-mknoon/node/pubsub.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go`. Command currently running: `cd go-mknoon && go test ./node -count=1 -run 'TestGroupKeyGraceChurn|TestGK017|TestGK018'`, then `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupGenerateNextKey'`. Decision/blocker: production change is minimal full key-info copy plus pre-generation active-grace guard. Next action: record gate results and run local QA review.
- 2026-05-23 23:32:16 CEST - GREEN gates complete; QA review starting. Files inspected or touched: scoped Go code/tests and this plan. Command currently running: none. Decision/blocker: both required commands passed: `ok github.com/mknoon/go-mknoon/node 4.110s` and `ok github.com/mknoon/go-mknoon/bridge 0.529s`. Next action: inspect scoped diff for scope adherence, behavior, missing required tests, and final verdict.
- 2026-05-23 23:33:02 CEST - QA review complete; final verdict written. Files inspected or touched: scoped diff, scoped file list, `git diff --check`, this plan. Command currently running: none. Decision/blocker: no blocking issues found; required tests exist and passed; `git diff --check` was clean; no fix pass used. Final verdict: accepted. Next action: report exact changed files and command results.
- 2026-05-23 23:37:02 CEST - Closure audit complete. Files inspected or touched: this plan, `group-key-grace-churn-session-breakdown.md`, and scoped GKGC code/test hunks in `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/bridge/bridge_generate_next_key_test.go`. Command currently running: none. Decision/blocker: controller-verified accepted execution closes GKGC-001; unrelated dirty hunks in the same code files remain outside this closure. Final verdict: closed.

## Closure Audit Verdict

Outcome: closed.

Completion Auditor classification:

- closed: `joinedGroupKeyInfo` now clones the complete incoming `GroupKeyInfo`, preserving supplied `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` while retaining nil and no-grace behavior.
- closed: `GroupGenerateNextKey` now rejects a second native rotation during active previous-key grace with `GROUP_KEY_GRACE_ACTIVE` before generating or returning key material.
- closed: focused regressions cover incoming grace preservation on join, no-grace join behavior, active-grace second-rotation rejection, and non-mutation of stored key/grace state after rejection.
- stale_doc: this plan and the breakdown previously read as execution/pending state; both are updated by this closure audit.
- residual_only: none inside GKGC-001.
- still_open: none for the host-only native closure bar.

Maintenance-time safety is defined by these controller-verified gates:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGroupKeyGraceChurn|TestGK017|TestGK018'
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupGenerateNextKey'
git diff --check on scoped files/docs
scripts/ensure_go_ios_bindings.sh
scripts/ensure_go_macos_bindings.sh
bash scripts/ensure_go_android_bindings.sh
scripts/verify_gomobile_bindings.sh all
```

Reopen only on a real regression in native joined-key grace preservation, active-grace generate-next-key rejection, or generated gomobile binding consistency. Do not reopen GKGC-001 for key-ring design, multi-previous-key retention, Flutter/UI handling of `GROUP_KEY_GRACE_ACTIVE`, relay/device proof, or unrelated dirty worktree changes.

## Evidence Collector Findings

- Breakdown source: `group-key-grace-churn-session-breakdown.md` originally classified GKGC-001 as `implementation-ready` with no dependency and limited scope to preserving incoming `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` while blocking `group:generateNextKey` during active grace.
- `node.GroupKeyInfo` already has `Key`, `KeyEpoch`, `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` fields in `go-mknoon/node/group.go`.
- At planning time, `go-mknoon/node/pubsub.go` stored joined key state through `joinedGroupKeyInfo`, and that helper copied only `Key` and `KeyEpoch`, so incoming previous-key grace metadata was dropped when `JoinGroupTopic`, `UpdateGroupKey` with no current state, or `RefreshJoinedGroupStateIfNewer` with no current key used that helper.
- Existing node rotation paths already create grace metadata when advancing from a current key: `RefreshJoinedGroupStateIfNewer` and `UpdateGroupKey` set previous key/epoch from current state and a new `GraceDeadline` when incoming epoch is newer.
- Existing validation/decryption only accepts previous epoch data while grace is active, via `hasKeyRotationGrace`, `verifyGroupEnvelopeSignature`, and `decryptGroupEnvelopePayload`.
- At planning time, `go-mknoon/bridge/bridge.go` `GroupGenerateNextKey` checked only for initialized node, valid input, and existing current key state before generating `KeyEpoch + 1`. It did not reject generation while `currentKeyInfo` had active previous-key grace.
- Before GKGC-001, direct node tests covered validator/decrypt grace behavior, `UpdateGroupKey` previous-key preservation, same/older epoch no-op behavior, initial joins with no grace when the incoming key had no grace metadata, and refresh/update behavior that derived grace from current state. They did not directly pin preservation of supplied grace metadata on joined key state.
- Before GKGC-001, bridge tests covered `GroupGenerateNextKey` validation, no mutation, missing key state, and use of restored committed epoch. They did not directly pin rejection while stored native key state had active grace.
- `Test-Flight-Improv/test-gate-definitions.md` is the named gate source for Flutter gates and does not define a device/simulator requirement for this Go-native session. The breakdown row's Go test commands are the session's exact host-side gates.

## real scope

Change only the native Go group key grace behavior for GKGC-001:

- Preserve supplied `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` when native joined key state is created from an incoming `node.GroupKeyInfo`.
- Reject `bridge.GroupGenerateNextKey` when the current native key state has active previous-key grace.
- Keep current validation/decryption grace semantics and current key update monotonicity unchanged.

This session does not add a key ring, does not retain multiple previous keys, and does not alter Flutter, SQLite, relay behavior, network protocols, group membership rules, or message encryption formats.

## closure bar

The session is complete when:

- Joining native key state from a `GroupKeyInfo` with live previous-key grace stores the same current key/epoch and same previous key/epoch/deadline.
- Joining with no supplied grace metadata still stores no grace metadata.
- `group:generateNextKey` still generates the next key when no grace window is active, still does not mutate stored state, and returns a clear error without `groupKey` or `keyEpoch` while a previous-key grace window is active.
- The exact host-only Go gates in this plan pass.

## source of truth

- Current code and direct Go tests are authoritative for implementation details.
- `Test-Flight-Improv/Group-Chat-Feature/group-key-grace-churn-session-breakdown.md` is authoritative for GKGC-001 scope and exact session gates.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative only for named Flutter gates; it does not expand this host-only Go session into device, simulator, relay, or real-network proof.
- If an existing test conflicts with the GKGC-001 row, update the test to the new session contract only when the conflict is specifically about immediate second rotation during active grace.

## session classification

closed

Planned as `implementation-ready`; execution was accepted and closure-audited on 2026-05-23.

## resolved problem statement

Native group key state previously lost supplied previous-key grace metadata when the state was created through joined-key cloning, because `joinedGroupKeyInfo` copied only `Key` and `KeyEpoch`. That could make a node unable to accept the previous epoch during a still-valid grace window after joining or restoring key state.

Native bridge callers could also call `group:generateNextKey` immediately after committing a rotation. Because `GroupGenerateNextKey` only checked for a current key and then returned `currentEpoch + 1`, it could produce a second rotation while the node was still inside the previous-key grace window. GKGC-001 closes this by making the operation a clear rejection rather than designing multi-key retention.

Current epoch sends, previous epoch validation during live grace, previous epoch rejection after grace, and monotonic key update behavior must stay unchanged.

## files and repos inspected for GKGC-001

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_generate_next_key_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/group-key-grace-churn-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_key_rotation_grace_test.go` covers validator/decrypt acceptance of previous epoch during live grace, rejection after grace, current epoch acceptance after grace, and `UpdateGroupKey` preserving a single previous key/deadline when advancing epochs.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go` includes `TestJoinGroupTopic_InitialKeyHasNoGraceState`, which should remain valid for incoming key state without grace metadata.
- `go-mknoon/node/pubsub_test.go` covers `RefreshJoinedGroupStateIfNewer` deriving previous-key grace from existing current state during a newer epoch refresh and preserving config/topic/subscription state.
- `go-mknoon/bridge/bridge_generate_next_key_test.go` covers validation errors, non-mutating generation, missing key state, and restored committed epoch behavior for `GroupGenerateNextKey`.
- Closed former coverage gap: direct tests now prove that supplied `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` survive joined-key cloning, and that `GroupGenerateNextKey` rejects during active grace.

## regression/tests added first

Implementation added or updated these tests before product-code changes and recorded the expected RED failures:

- Added `TestGroupKeyGraceChurnJoinGroupTopicPreservesIncomingGraceMetadata` in `go-mknoon/node/pubsub_key_rotation_grace_test.go`. The live-grace case joins a group with current key epoch 2, previous key epoch 1, and an exact incoming `GraceDeadline`; the no-grace case joins with only current key/epoch and asserts empty previous-key metadata.
- Added `TestGroupGenerateNextKey_GroupKeyGraceActiveRejectsSecondNativeRotation` in `go-mknoon/bridge/bridge_generate_next_key_test.go`. It creates a group, generates and commits the first next key, then verifies the immediate second generation returns `ok:false`, `GROUP_KEY_GRACE_ACTIVE`, and no generated key material while stored current/previous/deadline state remains unchanged.
- Updated the conflicting immediate second-generate expectation in `TestGroupGenerateNextKey_KE002UsesLatestCommittedEpochWithoutMutating` so active-grace generation rejects instead of succeeding. First-generation no-mutation assertions and restored/no-grace generation coverage remain in place.

## implemented steps

1. Added the node regression test for incoming grace preservation and observed the expected RED failure in the new test.
2. Added or adjusted the bridge regression tests for active-grace rejection and observed the expected RED failure/conflict in the immediate second-generate path.
3. Updated `go-mknoon/node/pubsub.go` so `joinedGroupKeyInfo` returns a full value copy of incoming `GroupKeyInfo` instead of dropping `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline`; nil handling remains unchanged.
4. Updated `go-mknoon/bridge/bridge.go` so `GroupGenerateNextKey` checks active previous-key grace before key generation and returns `errJSON("GROUP_KEY_GRACE_ACTIVE", "...")` without generated key material or native state mutation.
5. Ran the exact node and bridge Go commands from this plan and recorded accepted GREEN results.
6. Kept test expectation updates limited to the new active-grace contract; no grace-duration sleeps or test-only exported mutators were added.

## risks and edge cases

- `PrevKeyEpoch` can legitimately be `0` for first-rotation grace; active-grace checks must not require `PrevKeyEpoch > 0`.
- Copying incoming grace metadata must not synthesize grace when callers provide zero values.
- The bridge guard must run before key generation so rejected calls do not allocate or return unused key material.
- The bridge guard must not mutate stored current key, previous key, or deadline.
- Existing tests that expect immediate second generation are stale only for the active-grace window. Restored/no-grace generation should keep working.
- Avoid sleeps that wait for `KeyRotationGracePeriod`; they would make the host gate slow and flaky.

## exact tests and gates run

Direct RED/GREEN commands for this session:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGroupKeyGraceChurn|TestGK017|TestGK018'
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupGenerateNextKey'
```

No Flutter named gate is required for GKGC-001. No `flutter test`, simulator, device, relay fixture, or real-network command is part of the closure bar.

## known-failure interpretation used during implementation

Planning did not execute tests. During implementation, the two exact Go commands were run after adding RED tests and before behavior changes where practical. Failures in the newly added/updated GKGC tests were expected before implementation and were recorded in the execution progress. After implementation, the two exact commands passed.

## done criteria satisfied

- The plan's node regression exists and proves incoming joined key grace metadata is preserved.
- The plan's bridge regression exists and proves immediate second native rotation generation is rejected during active grace.
- `joinedGroupKeyInfo` preserves `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline` while keeping nil and no-grace behavior intact.
- `GroupGenerateNextKey` returns a clear active-grace error and no generated key material while grace is active.
- Existing current-epoch, previous-epoch grace, missing-key, restored-key, and non-mutating generation behavior remains covered by the exact commands.
- Both exact Go commands passed.

## scope guard

Do not:

- Design or implement a key ring, multi-previous-key storage, or grace queue.
- Change message envelope format, crypto primitives, key generation, group config schemas, Flutter bridge method names, Dart code, SQLite migrations, notifications, relay behavior, or real network setup.
- Add background timers, delayed retries, grace-expiry jobs, sleeps for the grace duration, or test-only exported mutators.
- Broaden this into group membership churn semantics beyond preserving already-supplied grace metadata and blocking one unsafe native generation command.

## accepted differences / intentionally out of scope

- This session intentionally accepts single previous-key grace rather than 1:1-style durable retry complexity or a group key ring.
- The bridge can reject active-grace generation even though older tests allowed immediate second generation; that older expectation is superseded only for the active-grace case.
- Flutter/UI handling of the new bridge error code is out of scope unless a later product session asks for user-facing messaging.
- Device, simulator, relay, and real-network proof are out of scope for this host-only native correctness session.

## dependency impact

GKGC-001 is the only session in the current breakdown. Later work can depend on native state retaining supplied previous-key grace metadata and on `group:generateNextKey` refusing a rapid second rotation during active grace. Implementation evidence did not require a key ring; future work should reopen decomposition only if a real regression proves single previous-key grace is insufficient.

## Device/Relay Proof Profile

- Proof type: host-only native Go package tests.
- Required devices: none.
- Required simulators: none.
- Required relay fixtures: none.
- Required real network: none.
- Acceptable evidence: the two exact `go test` commands in this plan, with focused RED-before/GREEN-after notes from the added/updated regressions.
- Non-evidence for closure: Flutter widget tests, device-backed integration tests, relay smoke tests, manual network runs, or screenshots.
