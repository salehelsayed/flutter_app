# GL-006 Plan: Join with nil key fails or creates explicit non-sendable state

Status: execution-ready

## Planning Progress

- 2026-05-10T01:46:00Z - Arbiter completed. Files inspected since last update: reviewer findings and final mandatory sections. Decision/blocker: no structural blockers; incremental details are intentionally deferred; accepted differences are documented. Plan is execution-ready for GL-006 only. Next action: hand off to implementation execution; do not edit source matrix or breakdown.
- 2026-05-10T01:45:42Z - Arbiter started. Files inspected since last update: reviewer findings, scope guard, accepted differences, and exact test/gate contract. Decision/blocker: no structural blocker identified entering arbitration. Next action: classify findings and finalize or block the plan.
- 2026-05-10T01:45:09Z - Reviewer completed. Files inspected since last update: full draft, mandatory section list, gate contract, GL-006 evidence notes, and scope guard. Decision/blocker: sufficient as-is; no structural blocker. The plan explicitly chooses reject-join, owns publish-after-rejection and pure inbound nil-key proof, and avoids GL-007/Flutter/state-machine scope. Next action: Arbiter classification and final status.
- 2026-05-10T01:44:36Z - Reviewer started. Files inspected since last update: planning draft and mandatory-section inventory. Decision/blocker: review in progress; checking whether the upfront rejection contract sufficiently covers publish and inbound attempts without hidden scope expansion. Next action: complete sufficiency review.
- 2026-05-10T01:43:04Z - Planner completed. Files inspected since last update: drafted mandatory plan sections against the evidence set. Decision/blocker: GL-006 is implementation-ready as one narrow production guard plus Go regressions; no Flutter, bridge, delivery redesign, key rotation, nil-config, or state-machine work is planned. Next action: reviewer sufficiency pass.

## real scope

Own exactly source row `GL-006`: `JoinGroupTopic(groupId, validConfig, nil)` must be explicit and non-dangerous. The GL-006 contract is:

- nil `keyInfo` is rejected up front for an unjoined group,
- the rejected join does not register/join/subscribe/store topic, subscription, config, key, subscription context, or discovery context state,
- `GetGroupKeyInfo(groupId)` remains nil after the rejection,
- `PublishGroupMessage(groupId, ...)` after the rejected join returns an explicit error instead of panicking or silently black-holing,
- inbound validation/decryption nil-key behavior is covered by direct Go helper proof.

This session may edit only `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`, plus this plan's progress/review sections during execution. `go-mknoon/node/pubsub_delivery_test.go` is inspection-only unless executor evidence proves the pure inbound proof is insufficient. `go-mknoon/node/node.go` is inspection-only; no new private test seam is expected for GL-006.

Out of scope: GL-007 nil config, key rotation, group delivery redesign, Flutter/bridge/Dart behavior, persisted group state, app resume/rejoin policy, invite status, and any general group topic state-machine refactor.

## closure bar

GL-006 is good enough when:

- The chosen contract is explicit: nil `keyInfo` is not a valid successful join input in the current architecture.
- A row-owned Go regression fails before the production guard because current `JoinGroupTopic` succeeds with nil `keyInfo`.
- The same regression passes after the production guard and proves no local group state is stored for the rejected join.
- The publish attempt after the rejected join returns a normal error, not a panic.
- A direct inbound validation/decryption proof covers nil-key behavior: validator helper returns a missing-key style rejection and decrypt helper returns `missing group key info`.
- Existing GL-001..GL-005 join-topic regressions still pass.
- No source matrix or session breakdown file is edited.

## source of truth

1. Current Go code and tests win for implementation details and reachable behavior.
2. Source matrix row `GL-006` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` wins for expected row behavior.
3. Session breakdown row `GL-006` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is planning context, but its broad Flutter/bridge owner list is narrowed by current code evidence.
4. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; if they disagree, the script wins.
5. This plan is the active execution contract once `Status: execution-ready` is written.

## session classification

`implementation-ready`

Disposition: code plus tests. Current code has a real product bug for GL-006: `JoinGroupTopic` stores `joinedGroupKeyInfo(nil)` into `n.groupKeys[groupId]`, creating a nil map value that makes the group look joined while later send/validation paths assume a non-nil `GroupKeyInfo`.

## exact problem statement

`JoinGroupTopic` currently accepts nil `keyInfo` for a valid config. It registers a validator, joins/subscribes to the topic, stores config/topic/subscription state, and stores `nil` in `groupKeys`. `PublishGroupMessage` checks only map presence, so the nil key value can reach `keyInfo.Key` and panic instead of returning a controlled missing-key or not-joined error.

The user-visible risk is a group that appears joined locally but cannot safely send or receive. The fix must make the behavior explicit and preserve all existing successful join, duplicate join, join failure cleanup, subscribe failure cleanup, and atomic successful-join behavior.

The current-architecture contract selected for GL-006 is upfront rejection. A non-sendable joined state is intentionally not chosen because it would require broader lifecycle semantics for publish, reaction, validation, decryption, rejoin, key repair, and UI state.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
  - `JoinGroupTopic`
  - `PublishGroupMessage`
  - `groupTopicValidator`
  - `decryptGroupEnvelopePayload`
  - `handleGroupSubscription`
  - `GetGroupKeyInfo`
  - `joinedGroupKeyInfo`
- `go-mknoon/node/pubsub_test.go`
  - validator helper `validateGroupEnvelope`
  - adjacent GL-001..GL-005 join-topic tests
  - new GL-006 regressions
- `go-mknoon/node/pubsub_delivery_test.go`
  - inspection only unless live inbound/delivery proof is proven necessary
- `go-mknoon/node/node.go`
  - inspection only; preserve existing dirty hook work and do not add a GL-006 seam
- `Test-Flight-Improv/test-gate-definitions.md`
  - gate source of truth only

## existing tests covering this area

- `TestJoinGroupTopic_FailsWithoutPubSub` covers GL-001 nil PubSub rejection and no attempted group state.
- `TestJoinGroupTopic_DuplicateJoinPreservesExistingState` and `TestJoinGroupTopic_DuplicateJoinPreservesDelivery` cover GL-002 duplicate join safety.
- `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` covers GL-003 join failure cleanup.
- `TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry` covers GL-004 subscribe failure cleanup.
- `TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish` covers GL-005 successful join state, immediate key lookup, and immediate publish.
- `validateGroupEnvelopeForTransportPeer` has nil-key logic returning `reject:no_key`, but there is no row-owned test that pins it.
- `decryptGroupEnvelopePayload` returns `missing group key info` for nil key info, but there is no row-owned test that pins it.
- `GetGroupKeyInfo_ReturnsNilForUnknownGroup` covers unknown group lookup only, not a nil-key join attempt.

Missing GL-006 coverage: no test proves nil `keyInfo` is rejected before local join state is stored, and no test proves publish/inbound nil-key attempts are explicit and non-panicking for this row.

## regression/tests to add first

Add the direct RED regression first in `go-mknoon/node/pubsub_test.go` near the adjacent `JoinGroupTopic` tests:

```go
func TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState(t *testing.T)
```

Test shape:

1. Start a local Go node with `Start(NodeConfig{AutoRegister: false})`.
2. Build a valid chat `GroupConfig` whose admin/writer member is `n.PeerId()` and whose public key comes from `generateEd25519KeyPair`.
3. Call `JoinGroupTopic(groupId, config, nil)`.
4. Before the production fix, the test must fail because `err == nil`.
5. After the production fix, assert the error string contains `missing group key info`.
6. Under `n.mu.RLock()`, assert no entries exist for that `groupId` in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx`.
7. Assert `GetGroupKeyInfo(groupId) == nil`.
8. Call `PublishGroupMessage` with the same group id and valid sender credentials. Assert it returns an error containing `group not joined` and does not panic. A panic is a GL-006 failure.

Add the direct inbound proof in `go-mknoon/node/pubsub_test.go` near validator tests:

```go
func TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey(t *testing.T)
```

Test shape:

1. Build a valid encrypted group envelope with a generated group key and valid member config.
2. Call `validateGroupEnvelope(envelopeJSON, groupId, config, nil)` and assert `reject:no_key`.
3. Parse the same envelope and call `decryptGroupEnvelopePayload(env, nil, time.Now())`.
4. Assert it returns an error containing `missing group key info` and no plaintext.

Do not add a live multi-node delivery test unless these direct tests cannot prove the row. Rejected join means there should be no live validator/subscription for the nil-key group.

## step-by-step implementation plan

1. Inspect the scoped current diff for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/node.go`; preserve user-owned dirty work.
2. Add `TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState`.
3. Run the direct GL-006 join test and record RED. Expected RED before production code: `JoinGroupTopic` returns nil for a nil key.
4. Add `TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey`.
5. Run the direct inbound proof. It may pass before production code because pure helper logic is already nil-safe; that is acceptable as supporting proof, not the RED driver.
6. In `JoinGroupTopic`, add the nil-key guard after the nil-PubSub and duplicate-join checks, before `topicName`, `RegisterTopicValidator`, `pubsub.Join`, or any map write:

```go
if keyInfo == nil {
    return fmt.Errorf("missing group key info for group %s", groupId)
}
```

7. Do not change `joinedGroupKeyInfo`, `GetGroupKeyInfo`, `UpdateGroupKey`, key rotation, validator registration, discovery loops, or publish/reaction semantics unless the direct GL-006 regression proves the join guard is insufficient.
8. Rerun the direct GL-006 join test and direct inbound proof; both must pass.
9. Rerun the row-level Go command and row-required Flutter startup rejoin smoke.
10. Run `git diff --check`.
11. QA must verify the final diff is limited to GL-006 production/test changes plus this plan's execution progress, and that no source matrix or breakdown file was edited.

Stop and return to planning if the nil-key guard breaks duplicate-join semantics, nil-PubSub semantics, successful join state, or requires Flutter/bridge changes.

## risks and edge cases

- Guard ordering matters. Nil PubSub must still return `pubsub not initialized`; duplicate join must still return `already joined`.
- The guard must run before validator registration, topic join, subscribe, map writes, handler goroutine start, and discovery goroutine start.
- Publish after rejected join should behave like an unjoined group and return `group not joined`; it must not enter encryption/signing.
- Inbound proof should stay pure and deterministic; live delivery proof would be heavier and unnecessary for a rejected join contract.
- Existing dirty work in the Go owner files must be preserved. Do not reformat or rewrite unrelated GL-001..GL-005 changes.
- `PublishGroupReaction` is not part of GL-006's row steps. Do not broaden into reaction hardening unless direct evidence proves the nil-key public join state remains reachable after the guard.

## exact tests and gates to run

Mandatory RED before production fix:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState$' -count=1)
```

Mandatory direct GREEN after production fix:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState$' -count=1)
(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey$' -count=1)
```

Mandatory row-level Go gate:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Mandatory row-required Flutter host smoke from the breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Mandatory hygiene:

```bash
git diff --check
```

Named gates: no full named gate is required for GL-006 if the final diff is limited to Go `JoinGroupTopic` nil-key rejection and Go tests. If execution touches Dart/Flutter group send, receive, retry, resume, invite, or announcement behavior, then run:

```bash
./scripts/run_test_gates.sh groups
```

## known-failure interpretation

No GL-006 known failure is accepted.

The direct GL-006 join test must fail before the production guard for the specific reason that `JoinGroupTopic` accepted nil `keyInfo`. If it does not fail before the guard, stop and inspect whether existing user-owned changes already fixed GL-006; do not duplicate behavior.

After the guard, all mandatory commands must pass. If a broader row command fails, classify it before any fix as one of: caused by GL-006, pre-existing, flaky, unrelated-but-required, or environment/tooling. Do not hide a new GL-006 failure behind existing dirty-worktree noise. Do not fix unrelated failures in this session.

## done criteria

- `Status: execution-ready` was present before execution began.
- The selected GL-006 contract is upfront nil-key rejection.
- The row-owned RED/GREEN join regression exists in `go-mknoon/node/pubsub_test.go`.
- The inbound nil-key proof exists in `go-mknoon/node/pubsub_test.go`.
- `go-mknoon/node/pubsub.go::JoinGroupTopic` rejects nil `keyInfo` before validator/topic/subscription setup or any map write.
- Required commands under `exact tests and gates to run` complete with no untriaged failures.
- Final diff excludes source matrix and session breakdown edits.

## scope guard

Do not:

- edit `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`,
- edit `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`,
- address GL-007 nil config,
- change group key rotation, previous-key grace behavior, or `UpdateGroupKey`,
- add a non-sendable joined state,
- add persisted local state migrations,
- change Flutter/bridge/Dart group lifecycle behavior,
- redesign validator, discovery, topic lifecycle, publish, reaction, or delivery semantics,
- add new private seams unless direct evidence proves direct helper tests cannot cover the row.

Overengineering for GL-006 includes adding a group join state enum, retry/key-repair workflow, UI state, bridge API, broad nil-key hardening across all group methods, or multi-node delivery tests when the chosen contract rejects the join before a live topic exists.

## accepted differences / intentionally out of scope

- Accepted difference: GL-006 allows either join rejection or explicit non-sendable state; this plan intentionally chooses join rejection because it is safer and narrower in the current Go architecture.
- Accepted difference: publish after the rejected join returns `group not joined`, not `missing group key info`, because no joined state should exist after the nil-key rejection.
- Accepted difference: live inbound validator/subscription diagnostics are not required for the rejected-join contract. The row-owned inbound proof is pure validation/decryption behavior.
- Accepted difference: `validateGroupEnvelope` helper currently names the nil-key result `reject:no_key`, while production validator diagnostics use `missing_key`; do not rename either unless a direct assertion requires consistency.
- Accepted difference: `PublishGroupReaction` is not included because the source row steps name `PublishGroupMessage` only.

## dependency impact

Closing GL-006 gives later group lifecycle and recovery sessions a clear invariant: a locally joined group always has non-nil group key info at join time. Later work may rely on `JoinGroupTopic` rejecting nil `keyInfo` instead of creating a non-sendable joined state.

If this plan changes to allow a non-sendable joined state, downstream rows touching key repair, startup rejoin, inbound diagnostics, publish/reaction behavior, bridge status, and Flutter group UI must be revisited before closure. GL-007 nil config remains separate and must not be inferred from GL-006.

## dirty-worktree note

At planning time, `git status --short` showed broad unrelated modified and untracked files, including existing edits in `go-mknoon/node/node.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` from adjacent group reliability work. This planning session created only this GL-006 plan file. Execution must preserve unrelated dirty work and inspect scoped diffs before editing.

## evidence notes

- `go-mknoon/node/pubsub.go:56` starts `JoinGroupTopic`; current nil-PubSub and duplicate checks happen before topic setup.
- `go-mknoon/node/pubsub.go:98` stores `joinedGroupKeyInfo(keyInfo)` into `groupKeys`; `joinedGroupKeyInfo(nil)` returns nil at `go-mknoon/node/pubsub.go:411`.
- `go-mknoon/node/pubsub.go:160` starts `PublishGroupMessage`; it checks map presence but can still receive a nil `keyInfo` value and later uses `keyInfo.Key`.
- `go-mknoon/node/pubsub.go:620` starts `groupTopicValidator`; it currently distinguishes absent key map entries, while the pure test helper returns `reject:no_key` for nil key info.
- `go-mknoon/node/pubsub.go:449` returns `missing group key info` from `decryptGroupEnvelopePayload` when key info is nil.
- Adjacent GL-001..GL-005 plans/tests already cover nil PubSub, duplicate join, join failure cleanup, subscribe failure cleanup, and successful join atomicity; GL-006 should not reopen those rows.

## reviewer findings

Reviewer verdict: sufficient as-is.

- Missing files, regressions, or gates: none blocking. `pubsub_delivery_test.go` and `node.go` remain inspection-only unless execution evidence contradicts the direct test strategy.
- Stale assumptions: none found. Current code evidence supports the bug and the chosen upfront rejection contract.
- Overengineering: none. The plan avoids a non-sendable joined state, Flutter/bridge changes, key repair, key rotation, and delivery redesign.
- Decomposition sufficiency: enough for implementation. One RED/GREEN join regression drives the production guard; one inbound helper proof covers nil-key validation/decryption without live topic setup.
- Minimum needed to make the plan sufficient: already present. The executor must preserve guard ordering and record RED/GREEN evidence for the direct GL-006 join test.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred:

- Live multi-node delivery or subscription-handler proof is deferred because the chosen contract rejects nil-key joins before a live topic/subscription exists.
- Full `./scripts/run_test_gates.sh groups` is deferred unless execution touches Dart/Flutter group behavior or broad group send/receive/resume surfaces.
- `PublishGroupReaction` hardening is deferred because the source row names `PublishGroupMessage` and the public nil-key join path becomes unreachable after the guard.

Accepted differences:

- Upfront join rejection is the selected GL-006 contract instead of explicit non-sendable joined state.
- Publish after rejection returns `group not joined` because there is no joined state after the fix.
- Pure validation/decryption proof is accepted for inbound nil-key behavior under this contract.

Final arbiter verdict: execution-ready for GL-006 only. No second review loop is required because no structural blocker was found.

## Execution Progress

- 2026-05-10T01:48:17Z - Executor fallback started. Files inspected since last update: plan, scoped dirty status/diff for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: nested spawned-agent tooling is unavailable in this session, so using the skill's local sequential fallback; broad pre-existing dirty work is present and must be preserved. Next action: add the GL-006 RED join regression only, then run the required RED command before production code changes.
- 2026-05-10T01:48:56Z - Executor RED test added. Files touched since last update: `go-mknoon/node/pubsub_test.go`. Command running: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState$' -count=1)`. Decision/blocker: production guard not yet added. Next action: record RED result and expected failure reason.
- 2026-05-10T01:49:17Z - Executor RED result recorded. Files touched since last update: none. Command finished: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState$' -count=1)` failed as expected. Decision/blocker: RED reason matches plan, `JoinGroupTopic` accepted nil `keyInfo` and logged joined topic before the test failed at `expected nil keyInfo join to fail`. Next action: add the direct inbound nil-key proof before the production guard.
- 2026-05-10T01:49:44Z - Executor inbound proof added. Files touched since last update: `go-mknoon/node/pubsub_test.go`. Command running: `(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey$' -count=1)`. Decision/blocker: production guard still not added; this command is supporting proof only and may already be green. Next action: record supporting result, then add the minimal join guard.
- 2026-05-10T01:50:05Z - Executor inbound proof result recorded. Files touched since last update: none. Command finished: `(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey$' -count=1)` passed. Decision/blocker: supporting helper proof is already green before the guard. Next action: add the minimal `JoinGroupTopic` nil-key guard after nil-PubSub and duplicate checks, before topic setup.
- 2026-05-10T01:50:29Z - Executor production guard applied. Files touched since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` via `gofmt`. Command running: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState$' -count=1)`. Decision/blocker: guard ordering matches the plan. Next action: run mandatory GREEN commands in order.
- 2026-05-10T01:51:03Z - Executor Go GREEN results recorded. Files touched since last update: none. Commands finished: direct GL-006 join regression passed, direct inbound proof passed, and `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` passed. Decision/blocker: no Go test blockers. Command running: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Next action: record Flutter smoke result, run `git diff --check`, then start local QA review.
- 2026-05-10T01:52:11Z - Executor completed and QA fallback started. Files inspected/touched since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, source matrix path, session breakdown path, and this plan. Commands finished: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed and `git diff --check` passed. Decision/blocker: no executor blocker; source matrix and session breakdown have no tracked diff and remain pre-existing untracked paths from before execution. Next action: QA review scope adherence, guard ordering, tests, and done criteria.
- 2026-05-10T01:52:34Z - QA fallback completed and final verdict written. Files inspected since last update: final scoped diff, line-level guard/test locations, status for guarded source matrix and session breakdown paths, and required command results. Decision/blocker: no blocking issues; no fix pass required. Final verdict: accepted. Next action: report exact execution verdict and command results.
- 2026-05-10T01:52:59Z - Final hygiene rechecked. Files touched since last update: this plan's execution progress only. Command finished: `git diff --check` passed after final progress update. Decision/blocker: final verdict remains accepted. Next action: report exact execution verdict.
