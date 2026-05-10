# GL-012 UpdateGroupConfig nil config handling plan

Status: execution-ready

## Execution Progress

- 2026-05-10 06:11:44 CEST - Phase: local QA completed / final verdict written. Files inspected/touched: GL-012 plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Command currently running: none. Decision/blocker: no blocking QA issues remain; GL-012 scope stayed Go-only for production, required regressions and all required commands passed, and source matrix/session breakdown were not updated. Next action: stop with final verdict `accepted`.
- 2026-05-10 06:11:10 CEST - Phase: local sequential fallback / groups gate rerun and diff hygiene passed. Files inspected/touched: GL-012 plan progress, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Command currently running: none. Decision/blocker: local rerun of `./scripts/run_test_gates.sh groups` passed with `00:05 +103: All tests passed!`; `git diff --check` exited 0 with no output. Next action: perform local QA against the plan and write final verdict.
- 2026-05-10 06:10:43 CEST - Phase: local sequential fallback / stalled Executor stopped. Files inspected/touched: GL-012 plan progress, `/tmp/gl012-executor2-result.md`, process table. Command currently running: none. Decision/blocker: nested Executor process was still running with an empty handoff file after recording groups-gate evidence, so it was stopped under the no-progress rule; local fallback will finish only required remaining evidence and QA. Next action: rerun/capture `./scripts/run_test_gates.sh groups`, run `git diff --check`, then perform local QA.
- 2026-05-10 06:09:59 CEST - Phase: Executor recovery pass / groups gate passed, diff hygiene started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `git diff --check`. Decision/blocker: `./scripts/run_test_gates.sh groups` passed with `00:07 +103: All tests passed!`. Next action: capture diff hygiene result.
- 2026-05-10 06:09:35 CEST - Phase: Executor recovery pass / Flutter startup rejoin smoke passed, groups gate started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: Flutter startup rejoin smoke passed with `00:00 +3: All tests passed!`. Next action: capture groups gate result.
- 2026-05-10 06:08:59 CEST - Phase: Executor recovery pass / row Go sweep passed, Flutter startup rejoin smoke started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Decision/blocker: row Go sweep passed with `ok github.com/mknoon/go-mknoon/node 16.562s`. Next action: capture Flutter startup rejoin smoke result.
- 2026-05-10 06:08:25 CEST - Phase: Executor recovery pass / race proof passed, row Go sweep started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)`. Decision/blocker: focused race command passed with `ok github.com/mknoon/go-mknoon/node 1.620s`. Next action: capture row sweep result and triage any failure.
- 2026-05-10 06:08:04 CEST - Phase: Executor recovery pass / focused test passed, race proof started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `(cd go-mknoon && go test -race ./node -run '^TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)`. Decision/blocker: focused non-race command passed with `ok github.com/mknoon/go-mknoon/node 0.545s`. Next action: capture race command result.
- 2026-05-10 06:07:45 CEST - Phase: Executor recovery pass / production edit complete, focused test started. Files inspected/touched: `go-mknoon/node/pubsub.go`, GL-012 plan progress. Command currently running: `(cd go-mknoon && go test ./node -run '^TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)`. Decision/blocker: `UpdateGroupConfig(groupId, nil)` now deletes `groupConfigs[groupId]`; publish/reaction/real validator/discovery/counter/find-member paths guard nil config. Next action: capture focused command result and triage if failing.
- 2026-05-10 06:06:47 CEST - Phase: Executor recovery pass / pre-fix focused test finished RED. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: none. Decision/blocker: focused command failed as expected; `TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic` panicked in `PublishGroupMessage` after `UpdateGroupConfig(groupId, nil)`, and `TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree` panicked in `dialKnownGroupMembers` at `pubsub.go:1260`. Next action: edit `go-mknoon/node/pubsub.go` only to delete nil configs and guard nil-config readers.
- 2026-05-10 06:05:59 CEST - Phase: Executor recovery pass / pre-fix focused test started. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: `(cd go-mknoon && go test ./node -run '^TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)`. Decision/blocker: current production still stores `cloneGroupConfig(nil)` in `groupConfigs`, so focused GL-012 tests should provide RED/compile evidence before production edits. Next action: capture focused command result and then make the smallest Go production fix.
- 2026-05-10 06:00:55 CEST - Phase: contract extracted. Files inspected/touched: GL-012 plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, dirty status. Command currently running: none. Decision/blocker: execution contract is concrete and Go-only for production changes; required evidence is focused Go direct tests, race proof, row Go sweep, Flutter startup rejoin smoke, groups gate, and `git diff --check`; bridge spot check is conditional only if bridge behavior/tests are touched. Next action: attempt fresh-isolated Executor spawn with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10 06:01:10 CEST - Phase: Executor spawned/running. Files inspected/touched: GL-012 plan progress only. Command currently running: `codex exec -m gpt-5.5 -c reasoning_effort="xhigh" -s danger-full-access -C /Users/I560101/Project-Sat/mknoon-2/flutter_app ...`. Decision/blocker: nested Executor materialization attempted through the local Codex CLI. Next action: wait bounded interval, then inspect child result evidence or classify spawn/no-progress.
- 2026-05-10 06:02:32 CEST - Phase: Executor local run / owner-file inspection. Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`; touched this progress entry only. Command currently running: none. Decision/blocker: required dirty diffs inspected before editing; current `UpdateGroupConfig` stores `cloneGroupConfig(nil)` as a present nil config and read paths still treat map presence as sufficient. Next action: add GL-012 RED tests in `go-mknoon/node/pubsub_test.go`.
- 2026-05-10 06:04:59 CEST - Phase: Executor spawn/no-progress recovery. Files inspected/touched: `go-mknoon/node/pubsub_test.go`, GL-012 plan progress. Command currently running: none. Decision/blocker: first Executor child was stopped after bounded waits without a trustworthy final result; it left partial GL-012 tests but no required test/gate evidence or production completion. Next action: spawn a fresh isolated Executor recovery pass with the new repo evidence and the same GL-012 contract.

## Final Execution Verdict

Final verdict: `accepted`.

Local QA result: no blocking issues and no non-blocking follow-ups for GL-012. Production scope stayed Go-only. `UpdateGroupConfig(groupId, nil)` now deletes the stored config; publish/reaction fail closed with `group not joined: <groupId>`; the real validator rejects unknown/config-disabled groups; direct discovery/counter helpers no-op safely; later valid config update repairs publish/validator behavior without rejoin. Required focused Go, race, row Go, Flutter startup smoke, groups gate, and diff hygiene evidence passed.

## Planning Progress

- 2026-05-10 05:59:10 CEST - Role: Arbiter completed. Files inspected since last update: reviewer findings and full GL-012 plan. Decision/blocker: no structural blockers remain; reviewer refinements were applied; plan is execution-ready. Next action: implement in a later execution session using this plan, preserving unrelated dirty work.
- 2026-05-10 05:58:40 CEST - Role: Reviewer completed / Arbiter started. Files inspected since last update: GL-012 draft plan only. Decision/blocker: plan is sufficient with minor non-structural adjustments: pin exact disabled-state error expectations and include both GL-012 direct tests in the non-race command. Next action: arbitrate findings, apply any accepted incremental refinements, and finalize readiness.
- 2026-05-10 05:57:18 CEST - Role: Planner completed / Reviewer started. Files inspected since last update: no new files; draft synthesized from collected evidence. Decision/blocker: smallest coherent behavior is Go-only fail-closed nil config handling: `UpdateGroupConfig(groupId, nil)` deletes local config, publish/reaction return existing not-joined style errors, validators reject unknown group, and discovery/counters no-op without panic. Next action: review sufficiency, scope guard, regression-first contract, and gate coverage.
- 2026-05-10 05:56:46 CEST - Role: Evidence Collector completed / Planner started. Files inspected since last update: source matrix GL-012 plus adjacent GL-011/GL-013/GL-019 rows, breakdown GL-012/GL-011 session rows and ledger, `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/bridge/bridge.go`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and targeted dirty status. Decision/blocker: current Go setter can store nil; publish/reaction/validator/direct discovery helpers can dereference that nil config; bridge/Dart changes are not evidenced. Next action: draft a Go-only fail-closed nil-config plan with direct regressions and gates.
- 2026-05-10 05:53:58 CEST - Role: Evidence Collector started. Files inspected since last update: none. Decision/blocker: collection will stay limited to GL-012 nil config behavior and directly adjacent group reliability gates. Next action: inspect matrix/breakdown, Go group config/publish/validator/discovery paths, related tests, and gate definitions.

## Evidence Collector Notes

- Source matrix GL-012 is P0/Open and asks for `UpdateGroupConfig(G, nil)`, publish, validate, discover, and race/panic proof. Expected behavior is no panic in `isAllowedWriter`, `findMember`, discovery, or counters, with tests defining the nil-config error or disabled state.
- Source matrix GL-011 is already Covered and explicitly leaves nil config to GL-012. GL-013+ key updates and GL-019 concurrent join/leave/update stress remain separate unresolved rows.
- Breakdown row GL-012 is `needs_code_and_tests`, `implementation-ready`, and names `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `group_startup_rejoin_smoke_test.dart`, and lifecycle recovery tests as the likely surface.
- `JoinGroupTopic` already rejects nil config before topic/validator/subscription/map writes. Existing GL-007 tests prove no join state is stored and publish fails as `group not joined` after rejected nil-config join.
- `UpdateGroupConfig` currently has no error return and stores `cloneGroupConfig(config)` directly in `n.groupConfigs[groupId]`; because `cloneGroupConfig(nil)` returns nil, `UpdateGroupConfig(groupId, nil)` creates a present map entry with a nil value.
- `PublishGroupMessage` checks only map presence before calling `isAllowedWriter(config, senderPeerId)`. `PublishGroupReaction` checks only map presence before calling `findMember(config, senderPeerId)`.
- The real `groupTopicValidator` checks only map presence before calling `findMember(config, env.SenderId)` and `isAllowedWriter(config, env.SenderId)`. The pure test helper already treats nil config as `reject:unknown_group`, but the real validator does not.
- `findMember` currently dereferences `config.Members` and has no nil guard. `isAllowedWriter` becomes nil-safe only if `findMember` becomes nil-safe, because it returns before reading `config.GroupType` when no member is found.
- `dialKnownGroupMembers` and `dialKnownGroupMembersDirectOnly` check map presence and host presence, but not nil config, before ranging over `config.Members` and emitting `totalMembers`. `countConnectedGroupMembers` checks map presence but not nil config before using `findMember`.
- `discoverAndConnectGroupPeers`, `expectedConnectedGroupMembers`, and `countRemoteGroupMembers` already tolerate nil config.
- `go-mknoon/bridge/bridge.go::GroupUpdateConfig` unmarshals `groupConfig` into a value and passes `&params.GroupConfig`, so no Dart/Flutter nil pointer change is evidenced for GL-012.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define `./scripts/run_test_gates.sh groups` for group send/receive/resume behavior. The breakdown also lists `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`.
- The targeted files are already dirty/untracked in this worktree, including `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, the source matrix, and the breakdown. Implementation must preserve unrelated dirty work and touch only GL-012 scope.

## real scope

Change only Go runtime nil-config handling and row-owned tests:

- make `UpdateGroupConfig(groupId, nil)` fail closed by removing the stored config for that group;
- make direct nil-config read paths return safe disabled/unknown-group behavior rather than panicking;
- add GL-012 regressions that drive publish, reaction, real validator, direct discovery helpers, counters, and a nil-update/read race proof;
- keep a later valid `UpdateGroupConfig` able to restore local send/validate behavior through the existing non-nil update path.

Do not change Dart/Flutter code, bridge JSON request shape, public group UI behavior, key update semantics, group join/leave lifecycle, GL-011 snapshot semantics, GL-013+ key update work, or GL-019 concurrent join/leave/update stress.

## closure bar

GL-012 is good enough when:

- `UpdateGroupConfig(groupId, nil)` can no longer store a present nil `*GroupConfig` that panics later;
- after nil config update on a joined group, `PublishGroupMessage` and `PublishGroupReaction` return errors without message IDs, peer counts, topic publishes, or panics;
- the real `groupTopicValidator` rejects an otherwise valid envelope as unknown/disabled group without panicking;
- direct discovery helpers and counters using group config return/no-op without panicking;
- a later valid `UpdateGroupConfig` can restore normal publish/validator behavior without rejoining or key rotation;
- focused direct tests, a race proof, the row Go sweep, required Flutter startup rejoin smoke, the named groups gate, and `git diff --check` pass or any unrelated pre-existing failures are documented precisely.

## source of truth

Authoritative, in order:

1. Current Go code and tests in `go-mknoon/node`.
2. `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh` for named gate membership; if they disagree, the script wins.
3. Source matrix row GL-012 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
4. Breakdown row GL-012 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

Current code and tests beat stale prose. GL-011 closure evidence remains authoritative for snapshot ownership and must not be reopened.

## session classification

`implementation-ready`

## exact problem statement

`UpdateGroupConfig` can currently accept nil and write a nil config pointer into `n.groupConfigs`. Because publish, reaction, validator, direct discovery, and connected-member counter paths treat map presence as sufficient, later calls can dereference `config.Members` through `findMember` or direct config iteration and panic.

User-visible behavior to improve: a bad nil config update must fail closed into a clear local disabled state instead of crashing or silently authorizing stale members. Sending should fail locally, inbound validation should reject, discovery should avoid using absent membership, and a valid config update should repair the group.

Must stay unchanged: valid config updates keep GL-011 snapshot behavior, nil join remains rejected by GL-007, key nil/update behavior remains GL-013+, join/leave lifecycle remains unchanged, and no Dart/Flutter API changes are introduced.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` only if existing discovery wait/assert helpers are reused
- `go-mknoon/bridge/bridge.go` only for confirming bridge behavior remains untouched
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

No Dart/Flutter files need editing unless implementation unexpectedly changes bridge or app-level behavior.

## existing tests covering this area

- `TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState` covers nil config at join time, not update time.
- `TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007` and `TestGroupTopicValidator_UnknownGroup` cover the pure validation helper's nil config behavior, not the real `groupTopicValidator` map-read path after `UpdateGroupConfig(nil)`.
- `TestUpdateGroupConfig_ReplacesConfigAtomically`, `TestUpdateGroupConfig_NonExistentGroup`, `TestUpdateGroupConfig_PreservesDiscoveryLoop`, and `TestUpdateGroupConfig_ConcurrentUpdates` cover valid config updates and concurrent writers, not nil config.
- GL-011 tests cover valid config snapshot ownership and validator/update race safety. They intentionally leave nil config for GL-012.
- Existing publish unjoined tests cover missing group map entries, not a joined group made config-disabled by nil update.

Missing: direct GL-012 tests that call `UpdateGroupConfig(groupId, nil)` on a joined group and then exercise publish, reaction, real validator, discovery helpers/counters, race/panic behavior, and valid-config repair.

## regression/tests to add first

Add tests before production edits:

1. `go-mknoon/node/pubsub_test.go::TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic`
   - Start a node, join a group with valid config/key, then call `UpdateGroupConfig(groupId, nil)`.
   - Assert no panic and that `groupConfigs[groupId]` is absent or treated absent; topic/sub/key/discovery context can remain because this is a config-disabled state, not leave.
   - Call `PublishGroupMessage` and `PublishGroupReaction`; assert no panic, publish returns empty message id and zero peer count, and both return the existing `group not joined: <groupId>` disabled-state error.
   - Build an otherwise valid envelope and call the real `groupTopicValidator(groupId)`; assert no panic and `pubsub.ValidationReject`.
   - Call `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, `countConnectedGroupMembers`, and `expectedConnectedGroupMembers`; assert no panic and zero/empty results where applicable.
   - Call `UpdateGroupConfig(groupId, validConfig)` again and assert publish/validator behavior is restored without rejoining or changing the key.

2. `go-mknoon/node/pubsub_test.go::TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree`
   - Use a real validator with a valid envelope and a node map setup that alternates `UpdateGroupConfig(groupId, nil)` and `UpdateGroupConfig(groupId, validConfig)`.
   - Concurrently run real validator reads plus `countConnectedGroupMembers` / discovery helper calls.
   - Under `go test -race`, expect only `ValidationAccept` or `ValidationReject` and no panic/race report.

3. Optionally add a tiny helper test only if needed to pin `findMember(nil, ...) == nil`; prefer covering it through publish/reaction/validator paths first.

## step-by-step implementation plan

1. Before editing, inspect current dirty diffs for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`; preserve unrelated GL-011 and earlier session changes.
2. Add the GL-012 tests above and run the focused direct command. Stop and reclassify if current code already passes, but expected RED is a panic or failed assertion around nil config after update.
3. In `UpdateGroupConfig`, handle nil before cloning:
   - lock as today;
   - if `config == nil`, `delete(n.groupConfigs, groupId)` and return;
   - otherwise store `cloneGroupConfig(config)` as GL-011 already requires.
4. Harden direct nil-config read paths in `pubsub.go`:
   - `findMember(nil, ...)` returns nil;
   - real `groupTopicValidator` treats missing or nil config as `unknown_group`;
   - `PublishGroupMessage` and `PublishGroupReaction` treat missing or nil config as not joined/config-disabled before authorization;
   - `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, and `countConnectedGroupMembers` return/no-op when config is nil.
5. Do not change `cloneGroupConfig(nil)` unless tests prove a direct need; keeping it nil-preserving is useful for callers and avoids reopening GL-011.
6. Keep bridge behavior unchanged unless a Go compile failure requires propagating a changed signature. Do not change the `UpdateGroupConfig` signature.
7. Run focused direct tests, race proof, row Go sweep, Flutter startup rejoin smoke, named groups gate, and diff hygiene.
8. Stop at GL-012. Do not update source matrix or breakdown closure docs in this implementation session unless a later closure/audit session asks for it.

## risks and edge cases

- Preserving stale config on nil update would avoid a send outage but could authorize removed members after local config loss; fail-closed deletion is safer for a reliability/security guard.
- Deleting config while leaving topic/sub/key/discovery context in place creates a deliberate config-disabled state, not a full leave. Tests must avoid claiming full cleanup.
- A nil config could also appear via direct test setup or future helper misuse; read-site nil guards protect those paths without broad architecture changes.
- Valid-config repair matters because app recovery may rehydrate config after a transient nil/missing state.
- Race tests should avoid GL-019 scope: no concurrent join/leave/key mutation, only nil/valid config updates plus reads.

## exact tests and gates to run

Focused direct tests:

```bash
(cd go-mknoon && go test ./node -run '^TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)
```

Focused race proof:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGL012UpdateGroupConfigNilDisablesJoinedGroupWithoutPanic$|^TestGL012UpdateGroupConfigNilConcurrentReadersAreRaceFree$' -count=1)
```

Row Go sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Bridge spot check only if bridge behavior or tests are touched:

```bash
(cd go-mknoon && go test ./bridge -run '^TestGroupUpdateConfig' -count=1)
```

Required Flutter smoke from the breakdown:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Named group gate from `test-gate-definitions.md` because group send/receive/validation behavior changes:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

## known-failure interpretation

- A RED focused GL-012 test before implementation is expected only if it proves the nil-update panic or disabled-state gap.
- Any post-fix panic, race detector report, compile failure, or focused GL-012 failure is blocking.
- Existing unrelated dirty-work failures in broader Flutter gates should be recorded with exact command output and must not be misclassified as GL-012 regressions unless they involve group config update, group publish/reaction, validator, discovery helper, or group startup rejoin behavior touched here.
- Do not remove tests from `test-gate-definitions.md` to make a gate green.

## done criteria

- GL-012 row-owned tests exist and fail against the old nil-storing behavior.
- Production code makes nil config update fail closed without panic and preserves valid config update behavior.
- `PublishGroupMessage`, `PublishGroupReaction`, real validator, direct discovery helpers, and counters are safe after nil config update.
- Valid config update after nil restores group send/validate behavior without rejoin or key update.
- Required direct Go, race, row sweep, Flutter smoke, groups gate, and `git diff --check` have passing evidence or precise unrelated-failure classification.
- No source matrix or breakdown closure overclaim is made by implementation.

## scope guard

Non-goals:

- no Dart/Flutter edits;
- no bridge JSON/API shape changes unless a compile-time consequence of a Go signature change forces a tiny Go bridge adaptation, which this plan avoids;
- no changes to `UpdateGroupKey(nil)`, key epochs, grace windows, decrypt diagnostics, or GL-013+ behavior;
- no join/leave cleanup semantics, validator unregister behavior, or group topic lifecycle changes;
- no broad concurrent join/leave/update stress harness for GL-019;
- no product UI, persistence, or recovery workflow changes.

Overengineering would include adding a new group state machine, new public errors through the Flutter bridge, background repair loops, new discovery seams, or test-only hooks when direct package tests can call existing unexported helpers.

## accepted differences / intentionally out of scope

- GL-012 accepts a local config-disabled state rather than full `LeaveGroupTopic` cleanup. Topic/sub/key/discovery context may remain so a later valid config update can repair the group.
- Bridge input validation for missing, null, or zero-value `groupConfig` is out of scope because the evidenced nil pointer path is Go-local `UpdateGroupConfig(groupId, nil)`.
- GL-011 remains closed; this plan does not re-review snapshot ownership except to avoid regressing it.
- GL-013+ key nil/epoch semantics and GL-019 concurrent lifecycle stress remain separate sessions.

## dependency impact

- GL-013 can rely on GL-012 having a clear distinction between config-disabled and key-disabled states.
- GL-019 should include nil/valid config update as one possible operation only after GL-012 lands, but should not duplicate GL-012's direct nil guard proof.
- Group recovery/rejoin work can treat a later valid `UpdateGroupConfig` as the repair path for config-disabled local state.

## Reviewer Findings

Verdict: sufficient with minor adjustments already applied.

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments.
- Missing files, tests, regressions, or gates: no structural omissions. The direct non-race command needed to include both GL-012 tests, and disabled-state publish/reaction errors needed exact wording.
- Stale or incorrect assumptions: none found. Current code confirms nil can be stored only through direct Go `UpdateGroupConfig`; bridge evidence does not require Dart/Flutter changes.
- Overengineering: none. The plan avoids signature changes, state machines, new hooks, and GL-019 stress expansion.
- Decomposition sufficiency: adequate. Implementation is limited to one `pubsub.go` behavior change plus direct Go tests and existing gates.
- Minimum needed: preserve dirty work, add RED GL-012 tests first, delete config on nil update, guard nil read paths, and run the listed direct/race/gate commands.

## Arbiter Decision

Structural blockers:

- None.

Incremental details:

- Reviewer-requested exact disabled-state error wording and the expanded direct non-race command were applied before finalization.

Accepted differences:

- The plan intentionally uses config deletion as a local disabled state instead of full leave cleanup.
- The plan intentionally keeps bridge/Dart validation out of scope because the evidenced nil pointer path is Go-local.
- The plan intentionally leaves GL-013+ key nil/epoch behavior and GL-019 lifecycle stress separate.

Arbiter verdict: `execution-ready`.

## Final Planning Output

Final verdict: `execution-ready`.

Final plan: add RED GL-012 Go tests first; make `UpdateGroupConfig(groupId, nil)` delete `groupConfigs[groupId]`; harden nil config read paths in publish, reaction, real validator, `findMember`, direct discovery helpers, and counters; prove publish/reaction return `group not joined: <groupId>`, validator rejects, discovery/counters no-op, and valid config update repairs the group without rejoin.

Structural blockers remaining: none.

Incremental details intentionally deferred: none for planning. Implementation may choose exact assertion helper placement based on current dirty diffs.

Accepted differences intentionally left unchanged: no Dart/Flutter or bridge shape changes; no full leave cleanup; no key update semantics; no GL-019 stress expansion.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/bridge/bridge.go`

Why the plan is safe to implement now: scope is bounded to one Go nil-config behavior and row-owned tests, GL-011 remains closed, GL-013+ and GL-019 stay separate, no public API/signature change is required, and the regression/gate contract directly exercises the panic surfaces named by GL-012.
