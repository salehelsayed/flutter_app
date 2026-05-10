# GL-011 UpdateGroupConfig Atomic Membership Plan

Status: execution-ready

## Planning Progress

- 2026-05-10 05:21:31 CEST - Evidence Collector starting. Files inspected since last update: implementation-plan-orchestrator skill instructions, intended plan path existence check. Decision/blocker: GL-011 source row and intended plan path are confirmed; no blocker. Next action: inspect the source matrix, session breakdown, Go group subscription/update code, direct tests, and gate definitions.
- 2026-05-10 05:26:00 CEST - Evidence Collector completed / Planner starting. Files inspected since last update: source matrix GL-011/GL-012/GL-019 rows, breakdown GL-011 inventory/rationale/ordered session, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_authorization_forward_test.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, `lib/core/bridge/bridge_group_helpers.dart`, `Test-Flight-Improv/test-gate-definitions.md`, and dirty worktree status. Decision/blocker: current code locks map replacement but stores caller-owned config pointers; existing tests cover replacement/concurrent updates but not active-delivery authorization or read/write race proof. Next action: draft the narrow code+tests plan.
- 2026-05-10 05:26:30 CEST - Planner completed / Reviewer starting. Files inspected since last update: no new files; draft synthesized from collected evidence. Decision/blocker: smallest coherent plan is Go-only config snapshot ownership plus row-named active subscription and validator read/write race regressions. Next action: review sufficiency, scope boundaries, and gate contract.
- 2026-05-10 05:27:19 CEST - Reviewer completed / Arbiter starting. Files inspected since last update: GL-011 draft plan. Decision/blocker: plan is sufficient with no structural blocker; tests, gate contract, scope guard, and dirty-worktree cautions are explicit. Next action: arbitrate review findings and finalize execution readiness.
- 2026-05-10 05:27:47 CEST - Arbiter completed. Files inspected since last update: reviewer pass and full GL-011 plan. Decision/blocker: no structural blockers remain; incremental details are documented and do not require another planning loop. Next action: execute this plan in a later implementation session.

## Execution Progress

- 2026-05-10 05:29:07 CEST - Controller contract extracted. Files inspected/touched: execution-qa skill, GL-011 plan, `git status --short`, dirty diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`; touched this plan only for heartbeat. Command running: none. Decision/blocker: contract is concrete, Go-only except required Flutter/group gates; target files already contain unrelated dirty GL-001/002/003/004/005/006/007/009 work that must be preserved. Next action: spawn fresh Executor agent with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-05-10 05:31:06 CEST - Executor spawn attempt corrected. Files inspected/touched: this plan only. Command running: failed `codex exec ... -a never ...` before child materialization. Decision/blocker: CLI flag placement failure, no child work or hidden state produced. Next action: retry Executor spawn with approval policy passed as a top-level Codex option.
- 2026-05-10 05:30:46 CEST - Executor spawned/running; contract extracted. Files inspected/touched: implementation-execution-qa-orchestrator skill, this GL-011 plan, dirty worktree status. Decision/blocker: scope is Go-only config snapshot ownership with row-owned GL-011 tests; no blocker. Next action: inspect dirty diffs and code-entry files before edits.
- 2026-05-10 05:32:46 CEST - Executor inspected dirty diffs and code-entry files. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_authorization_forward_test.go`. Decision/blocker: pre-existing dirty GL-001 through GL-009 edits include pointer-identity config expectations that GL-011 must update without reverting unrelated work. Next action: add RED GL-011 tests first.
- 2026-05-10 05:34:58 CEST - Executor added RED GL-011 tests and formatted touched Go tests. Files inspected/touched: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: production code not changed yet; snapshot test should expose caller-owned config aliasing. Next action: run focused RED command.
- 2026-05-10 05:35:11 CEST - Focused RED command started. Command: `(cd go-mknoon && go test ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$' -count=1)`. Decision/blocker: awaiting expected pre-fix failure. Next action: inspect result.
- 2026-05-10 05:35:39 CEST - Focused RED command finished. Outcome: failed as expected in `TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads` because validator followed caller mutation instead of stored snapshot; classified as this-session pre-fix failure. Decision/blocker: no blocker. Next action: add config clone helper and store owned snapshots in `JoinGroupTopic` and `UpdateGroupConfig`.
- 2026-05-10 05:37:04 CEST - Executor implemented config snapshot ownership. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`. Decision/blocker: `JoinGroupTopic` and `UpdateGroupConfig` now store `cloneGroupConfig` snapshots; stale config pointer-identity tests were updated to value/snapshot expectations. Next action: run required focused direct command.
- 2026-05-10 05:37:21 CEST - Required focused direct command started. Command: `(cd go-mknoon && go test ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$' -count=1)`. Decision/blocker: awaiting result. Next action: record outcome.
- 2026-05-10 05:37:42 CEST - Required focused direct command finished. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 4.030s`). Decision/blocker: no blocker. Next action: run required race proof.
- 2026-05-10 05:37:57 CEST - Required race proof started. Command: `(cd go-mknoon && go test -race ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$' -count=1)`. Decision/blocker: awaiting result. Next action: record outcome.
- 2026-05-10 05:38:32 CEST - Required race proof finished. Outcome: FAILED with a test-helper race assigning `eventCallback` after node start in `startLocalNodeForMultiRelayTestWithCollector`, not a config snapshot race. Classification: this-session test setup blocker because GL-011 active subscription test uses the helper under the required race command. Next action: make the helper construct collector-backed nodes before `Start`.
- 2026-05-10 05:39:01 CEST - Executor fixed race-only test setup blocker. Files inspected/touched: `go-mknoon/node/pubsub_delivery_test.go`; existing dirty `go-mknoon/node/node.go` hook state was preserved. Decision/blocker: collector-backed local nodes now use `New(collector)` before `Start`, avoiding post-start callback mutation. Next action: rerun required race proof.
- 2026-05-10 05:39:17 CEST - Required race proof rerun started. Command: `(cd go-mknoon && go test -race ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$' -count=1)`. Decision/blocker: awaiting result. Next action: record outcome.
- 2026-05-10 05:40:20 CEST - Local sequential fallback started after stalled nested Executor. Files inspected/touched: process list, `/tmp/gl011_executor_result.md`, this plan, landed diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/node.go`; touched this plan to consolidate duplicate progress. Command running: stopped nested Executor PIDs 47620 and 47621. Decision/blocker: no trustworthy child handoff appeared and the race rerun had no recorded outcome; landed code/tests are now repo state to verify locally. Next action: run required direct tests and gates locally, then perform local QA.
- 2026-05-10 05:41:02 CEST - Local focused direct command started. Command: `(cd go-mknoon && go test ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$' -count=1)`. Files inspected/touched: none. Decision/blocker: awaiting local result. Next action: record outcome.
- 2026-05-10 05:41:09 CEST - Local focused direct command finished. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 4.044s`). Files inspected/touched: none. Decision/blocker: no blocker. Next action: run local required race proof.
- 2026-05-10 05:41:09 CEST - Local required race proof started. Command: `(cd go-mknoon && go test -race ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$' -count=1)`. Files inspected/touched: none. Decision/blocker: awaiting local race result. Next action: record outcome.
- 2026-05-10 05:41:16 CEST - Local required race proof finished. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 5.231s`). Files inspected/touched: none. Decision/blocker: no blocker. Next action: run local row Go sweep.
- 2026-05-10 05:41:16 CEST - Local row Go sweep started. Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)`. Files inspected/touched: none. Decision/blocker: awaiting local result. Next action: record outcome.
- 2026-05-10 05:41:34 CEST - Local row Go sweep finished. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 16.463s`). Files inspected/touched: none. Decision/blocker: no blocker. Next action: bridge spot check not required because bridge behavior/tests were not touched; run required Flutter startup rejoin smoke.
- 2026-05-10 05:41:34 CEST - Local Flutter startup rejoin smoke started. Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Files inspected/touched: none. Decision/blocker: awaiting local result. Next action: record outcome.
- 2026-05-10 05:42:46 CEST - Local Flutter startup rejoin smoke finished. Outcome: PASS (`00:00 +3: All tests passed!`). Files inspected/touched: none. Decision/blocker: no blocker. Next action: run required named groups gate.
- 2026-05-10 05:42:46 CEST - Local named groups gate started. Command: `./scripts/run_test_gates.sh groups`. Files inspected/touched: none. Decision/blocker: awaiting local result. Next action: record outcome.
- 2026-05-10 05:43:11 CEST - Local named groups gate finished. Outcome: PASS (`00:11 +103: All tests passed!`). Files inspected/touched: none. Decision/blocker: no blocker. Next action: run diff hygiene check.
- 2026-05-10 05:43:11 CEST - Local diff hygiene check started. Command: `git diff --check`. Files inspected/touched: none. Decision/blocker: awaiting local result. Next action: record outcome and perform local QA.
- 2026-05-10 05:43:17 CEST - Local diff hygiene check finished. Outcome: PASS (no output). Files inspected/touched: none. Decision/blocker: no blocker. Next action: perform local QA review against GL-011 scope, tests, gates, and done criteria.
- 2026-05-10 05:43:17 CEST - Local QA Reviewer started. Files inspected/touched: GL-011 plan, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and local test/gate evidence. Command running: none. Decision/blocker: checking scope adherence and sufficiency. Next action: record QA outcome and final verdict.
- 2026-05-10 05:44:20 CEST - Local QA Reviewer completed. Files inspected/touched: GL-011 plan, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and local test/gate evidence. Command running: none. Decision/blocker: no blocking issues; scope stayed Go/test-only, required GL-011 regressions exist, config snapshots deep-copy members/devices, required direct tests/gates passed, and bridge spot check was not required because bridge files were not touched. Next action: write final verdict.
- 2026-05-10 05:44:20 CEST - Final verdict written. Verdict: accepted. Files inspected/touched: this plan. Command running: none. Decision/blocker: GL-011 done criteria met with no non-blocking follow-ups deferred. Next action: return compact final report.
- 2026-05-10 05:45:46 CEST - Recovery verification started. Files inspected/touched: execution-qa skill, this GL-011 plan, `git status --short`, and landed diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/node.go`; touched this plan only for recovery heartbeat. Command running: none. Decision/blocker: spawned sub-agent tool is unavailable in this session, so recovery remains in bounded local sequential fallback; landed code/tests look coherent for GL-011 and unrelated GL-001..GL-009 dirty work will be preserved. Next action: rerun the plan-required direct tests and gates from current repo state.
- 2026-05-10 05:46:11 CEST - Recovery focused direct command finished. Command: `(cd go-mknoon && go test ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$' -count=1)`. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 3.842s`). Files inspected/touched: none beyond this heartbeat. Decision/blocker: no blocker. Next action: run required GL-011 race proof.
- 2026-05-10 05:46:32 CEST - Recovery required race proof finished. Command: `(cd go-mknoon && go test -race ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$' -count=1)`. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 5.319s`). Files inspected/touched: none beyond this heartbeat. Decision/blocker: no blocker. Next action: run row Go sweep.
- 2026-05-10 05:47:07 CEST - Recovery row Go sweep finished. Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)`. Outcome: PASS (`ok github.com/mknoon/go-mknoon/node 16.579s`). Files inspected/touched: none beyond this heartbeat. Decision/blocker: no blocker; bridge spot check remains not required because `go-mknoon/bridge` behavior/tests were not touched. Next action: run required Flutter startup rejoin smoke.
- 2026-05-10 05:47:26 CEST - Recovery Flutter startup rejoin smoke finished. Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Outcome: PASS (`00:00 +3: All tests passed!`). Files inspected/touched: none beyond this heartbeat. Decision/blocker: no blocker. Next action: run required named groups gate.
- 2026-05-10 05:47:50 CEST - Recovery named groups gate finished. Command: `./scripts/run_test_gates.sh groups`. Outcome: PASS (`00:07 +103: All tests passed!`). Files inspected/touched: none beyond this heartbeat. Decision/blocker: no blocker. Next action: run diff hygiene check.
- 2026-05-10 05:48:29 CEST - Recovery diff hygiene and local QA completed. Commands: `git diff --check` PASS (no output). Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/node.go`, current status, and this plan heartbeat. Decision/blocker: no blocking issues; `JoinGroupTopic` and `UpdateGroupConfig` store owned snapshots, `cloneGroupConfig` deep-copies members/devices, GL-011 active subscription/snapshot/race tests exist and passed under the required commands, and unrelated dirty GL-001..GL-009 work was preserved. Next action: write recovery final verdict.
- 2026-05-10 05:48:40 CEST - Recovery final verdict written. Verdict: accepted. Files inspected/touched: this plan. Command running: none. Decision/blocker: GL-011 sufficiency rule met with no blocking issues and no non-blocking follow-ups deferred. Next action: return compact final report.

## Evidence Collector Notes

- Source matrix row GL-011 is `Open`, P0, and expects active-subscription messages to be authorized by either the old config before update or the new config after update, with no mixed or panic window.
- Adjacent source rows keep nil config separate in GL-012, key updates separate in GL-013 through GL-016, and concurrent join/leave/update stress separate in GL-019.
- Breakdown row GL-011 is `needs_code_and_tests`, `implementation-ready`, and names `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` as the direct Go surface.
- `Node.mu` is a `sync.RWMutex` guarding `groupConfigs` and `groupKeys` maps. `UpdateGroupConfig` locks and replaces the map entry, but it stores the caller-owned `*GroupConfig` pointer.
- `groupTopicValidator` reads `n.groupConfigs[groupId]` under `RLock`, releases the lock, then calls `findMember`, `activeMemberDeviceForEnvelope`, and `isAllowedWriter` on the captured pointer. This makes map replacement atomic, but it does not make the stored config object or nested `Members` / `Devices` slices immutable.
- `handleGroupSubscription` does not read `groupConfigs`; it reads `groupKeys` for decrypt. GL-011 should not change key rotation or decrypt fallback behavior.
- `GroupConfig` contains `Members []GroupMember`, and `GroupMember` contains `Devices []GroupMemberDevice`. A config snapshot must deep-copy both slices.
- Existing config tests cover simple pointer replacement, non-existent group storage, preserving discovery loop, concurrent `UpdateGroupConfig` writers, and pure validator concurrency. They do not cover live delivery before/after membership update or concurrent validator reads while `UpdateGroupConfig` receives caller-owned config objects.
- Existing delivery helpers in `pubsub_delivery_test.go` and `group_security_harness_test.go` can start local nodes, connect topics, publish raw envelopes, wait for received events, wait for validation rejects, and assert no marker delivery.
- `go-mknoon/bridge/bridge.go::GroupUpdateConfig` unmarshals JSON into a value and passes `&params.GroupConfig` to `n.UpdateGroupConfig`. No Dart/Flutter behavior change is evidenced for GL-011.
- `Test-Flight-Improv/test-gate-definitions.md` says `./scripts/run_test_gates.sh groups` is the named gate when group send/receive behavior changes. The breakdown also requires `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`.
- The worktree is already dirty in `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and many unrelated files. Implementation must preserve unrelated dirty work.

## real scope

Change only Go group config ownership and GL-011 tests:

- add a private config snapshot helper in `go-mknoon/node/pubsub.go` or an adjacent Go file in the same package;
- use that helper when storing non-nil configs in `JoinGroupTopic` and `UpdateGroupConfig`;
- add row-named GL-011 regressions proving active subscription behavior before/remove/re-add and validator read/write race safety;
- adjust only directly affected existing Go tests whose pointer-identity expectations become stale after config snapshotting.

Do not change Dart/Flutter code, bridge request shape, public method signatures, key update semantics, nil config behavior, leave/join lifecycle, discovery policy, peer scoring, or product UX in this session.

## closure bar

GL-011 is good enough when:

- a joined group stores an owned snapshot of membership config rather than a caller-owned mutable pointer;
- an active subscription can receive from member C before update, reject C after C is removed, and receive from C again after C is re-added without rejoining the topic or changing keys;
- validator/update race proof passes under `go test -race`;
- existing join/update/config tests still pass with value/snapshot expectations;
- no GL-012 nil-config behavior, GL-013+ key behavior, or GL-019 join/leave/update stress behavior is claimed.

## source of truth

Authoritative, in order:

1. Current Go code and tests in `go-mknoon/node`.
2. `Test-Flight-Improv/test-gate-definitions.md` for named gates.
3. Source matrix row GL-011 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
4. Breakdown GL-011 session entry in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

If prose conflicts with current code, current code wins. If gate prose conflicts with scripts, `scripts/run_test_gates.sh` wins.

## session classification

`implementation-ready`

## exact problem statement

`UpdateGroupConfig` currently replaces the `groupConfigs` map entry under lock, but stores the caller-provided `*GroupConfig` directly. Validators and discovery helpers then read the captured config pointer outside the lock. During active subscription, this can leave authorization dependent on a mutable caller-owned slice rather than an immutable old-or-new membership snapshot.

User-visible behavior to protect: a member added or removed from a private group must have live PubSub authorization follow the update without a rejoin and without a transient panic, stale accept, or mixed membership view.

Must stay unchanged: nil config remains GL-012, key update and epoch behavior remain GL-013 through GL-016, concurrent join/leave/update stress remains GL-019, and no Flutter API shape changes are introduced.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_authorization_forward_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`

No Dart files need editing unless Go bridge behavior evidence changes during implementation.

## existing tests covering this area

- `TestUpdateGroupConfig_ReplacesConfigAtomically` proves the map entry changes to a new config shape but does not prove snapshot ownership or active delivery.
- `TestUpdateGroupConfig_NonExistentGroup` pins current silent storage for unjoined groups; do not change it in GL-011.
- `TestUpdateGroupConfig_PreservesDiscoveryLoop` proves config updates do not cancel discovery.
- `TestUpdateGroupConfig_ConcurrentUpdates` proves concurrent writers do not corrupt the final map entry under race, but does not include validator reads.
- `TestGroupTopicValidator_ConcurrentValidation` proves concurrent pure validation on one config/key, but does not include `UpdateGroupConfig`.
- `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate` proves removed peers are excluded from known/discovered dialing after update, not active PubSub delivery.
- `TestGL009LeaveGroupTopicUnregistersValidatorAndRejoinUsesLatestConfigKey` provides useful delivery helper patterns for latest-vs-stale validation.

Missing: row-owned GL-011 proof for active subscription delivery across config update and direct validator read/write race proof.

## regression/tests to add first

Add tests before production edits:

1. `go-mknoon/node/pubsub_delivery_test.go::TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription`
   - Start local nodes A, B, and C on one group with B collecting events.
   - Join B once and keep its subscription handler active for the full test.
   - With old config containing C, publish from C and assert B receives the marker.
   - Call `nodeB.UpdateGroupConfig` with a config that removes C, publish from C again, assert B emits `group:validation_rejected` with `non_member` and does not receive that marker.
   - Call `nodeB.UpdateGroupConfig` with a config that re-adds C using the same key epoch/key, publish from C again, and assert B receives the new marker.

2. `go-mknoon/node/pubsub_test.go::TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads`
   - Use the real `groupTopicValidator`, not only the pure helper.
   - Prove a config passed into `UpdateGroupConfig` is snapshotted by mutating the caller-owned config after update and asserting validator authorization follows the stored update snapshot, not the later caller mutation.

3. `go-mknoon/node/pubsub_test.go::TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree`
   - Run validators concurrently with repeated `UpdateGroupConfig` calls using caller-owned configs that are mutated after the call returns.
   - Under `go test -race`, this should fail before config snapshot ownership and pass after it.
   - Assert every validator result is either `ValidationAccept` or `ValidationReject`; any panic or race detector report blocks closure.

## step-by-step implementation plan

1. Re-read the current dirty diffs in `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` before editing so unrelated work is preserved.
2. Add the GL-011 tests above and run the focused direct commands to confirm the expected failure shape. Stop if tests already pass without production changes and reclassify as tests-only evidence.
3. Add a private helper such as `cloneGroupConfig(config *GroupConfig) *GroupConfig` that:
   - returns `nil` for nil input to avoid taking over GL-012;
   - shallow-copies scalar fields;
   - deep-copies `Members`;
   - deep-copies each member's `Devices`.
4. Store `cloneGroupConfig(config)` in `JoinGroupTopic` and `UpdateGroupConfig`.
5. Update directly affected existing Go tests that asserted config pointer identity so they assert value/snapshot semantics instead. Do not weaken checks about duplicate join preserving the first stored config content.
6. Re-run focused GL-011 tests, the direct race proof, the row Go sweep, and the required Flutter/group gates.
7. Stop at GL-011 closure. Do not update source matrix or breakdown during implementation unless a later closure/audit session asks for it.

## risks and edge cases

- Existing dirty tests from GL-002/GL-005 may assert pointer identity for joined configs; snapshot ownership intentionally changes that internal detail.
- A shallow config copy would still alias nested `Members` or `Devices` slices and would not satisfy GL-011.
- Holding `n.mu` while running full validation would reduce concurrency and risks deadlocks or unnecessary lock contention; snapshot ownership is the smaller fix.
- Do not combine config and key reads or change key grace behavior; that belongs to GL-013 through GL-016 unless a GL-011 test proves an immediate dependency.
- Active subscription tests can be timing-sensitive; use existing local-node helpers and bounded event waiters rather than sleeps as assertions.

## exact tests and gates to run

Focused direct tests:

```bash
(cd go-mknoon && go test ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$' -count=1)
```

Race proof:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription$|^TestGL011UpdateGroupConfigSnapshotsMembershipForValidatorReads$|^TestGL011UpdateGroupConfigConcurrentValidatorReadsAreRaceFree$' -count=1)
```

Row Go sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Bridge spot check if `GroupUpdateConfig` behavior or tests are touched:

```bash
(cd go-mknoon && go test ./bridge -run '^TestGroupUpdateConfig_WithNewMember$' -count=1)
```

Required Flutter smoke from the breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named group gate from `test-gate-definitions.md` because group send/receive authorization changes:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

## known-failure interpretation

- Direct GL-011 tests or the GL-011 race command must be green; any failure there is a session blocker.
- A failure in pre-existing dirty work is only classifiable as pre-existing if it is unrelated to GL-011 files/commands or can be reproduced before GL-011 edits. Record exact command output and do not mark GL-011 complete on assumption.
- If `./scripts/run_test_gates.sh groups` fails in a known unrelated Flutter test, rerun the required direct Flutter smoke and focused Go commands. The final report must name the failing test and whether it is outside the Go config-update surface.

## done criteria

- GL-011 row-named active subscription test exists and passes.
- GL-011 snapshot/race tests exist and pass, including under `go test -race`.
- `JoinGroupTopic` and `UpdateGroupConfig` store owned config snapshots for non-nil configs.
- Existing update/join/discovery tests pass after any necessary value-expectation updates.
- Required direct Go, race, row Go, Flutter smoke, group gate, and diff-check commands are run or any inability to run is documented with a concrete reason.
- No Dart/Flutter source files are edited unless implementation discovers direct evidence requiring it.

## scope guard

Non-goals:

- Do not solve `UpdateGroupConfig(nil)`; that is GL-012.
- Do not change `UpdateGroupKey`, key epochs, previous-key grace, or decryption fallback; those are GL-013 through GL-016.
- Do not add concurrent join/leave/update stress coverage; that is GL-019.
- Do not alter bridge JSON shape, app group repository behavior, invite UX, member removal UX, peer scoring, forced disconnect, or relay/rendezvous policy.
- Do not introduce a new config store abstraction or broad refactor; a small clone helper is enough if tests prove the seam.

Overengineering would include replacing `Node.mu`, adding per-group locks, changing validator APIs, or making Flutter changes without Go evidence.

## accepted differences / intentionally out of scope

- GL-011 accepts the shipped ignore/filter policy: removed members are rejected by validation, not necessarily disconnected or downscored.
- Active delivery proof can use deterministic local libp2p nodes and raw or normal PubSub publishes; it does not need a three-simulator E2E run in this session.
- The bridge can continue passing `&params.GroupConfig`; the Go node owns snapshotting at the boundary.

## dependency impact

- GL-012 should build on this plan by deciding nil-config behavior separately.
- GL-013 through GL-016 should not be started until GL-011 is stable, because their key behavior tests may share validator/delivery helpers.
- GL-019 should include join/leave/update stress only after GL-011 establishes config snapshot ownership; if GL-011 changes away from snapshot ownership, GL-019 must revisit its race assumptions.

## Reviewer Pass

Verdict: sufficient as-is.

Sufficiency review answers:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None structurally. The plan names the production Go file, direct tests, delivery helpers, bridge spot check, row Go sweep, direct race proof, Flutter smoke, named groups gate, and diff check.
- What assumptions are stale or incorrect? None found. The plan correctly treats current code as authoritative and notes that existing pointer-identity expectations may become stale once configs are snapshotted.
- What is overengineered? No overengineering found. A clone helper is narrower than lock redesign, per-group locks, bridge changes, or Flutter changes.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It separates active delivery proof, deterministic snapshot proof, and race proof, while keeping GL-012, GL-013+, and GL-019 out of scope.
- Minimum needed to make the plan sufficient: already present.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers:

- None.

Incremental details:

- Executor may place `cloneGroupConfig` in `pubsub.go` near the key clone helpers or in a small same-package file.
- Executor may use normal `PublishGroupMessage` or raw envelope publish in the active subscription test, as long as B's real validator and subscription handler are exercised.
- Bridge spot check is required only if bridge behavior/tests are touched; otherwise it remains a low-cost optional confirmation.

Accepted differences intentionally left unchanged:

- No forced disconnect/downscore proof for removed C.
- No simulator 3-party E2E proof in this session.
- No nil-config, key-update, or join/leave/update stress behavior changes.
- No Dart/Flutter source changes unless implementation discovers new evidence.

Why safe to implement now:

- The plan has a narrow production change, regression-first tests, a direct race command, exact gates, dirty-worktree guardrails, and explicit non-goals for adjacent GL rows.
