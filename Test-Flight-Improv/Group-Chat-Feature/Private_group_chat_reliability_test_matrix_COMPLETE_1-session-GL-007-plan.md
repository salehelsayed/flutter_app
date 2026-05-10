# GL-007 Nil Group Config Join Reliability Plan

Status: execution-ready

## Planning Progress

- 2026-05-10 04:05:46 CEST | Role: Arbiter completed | Files inspected since last update: reviewer findings, mandatory sections, accepted differences, dependency impact, stop rule | Decision/blocker: no structural blockers remain; no second review loop required. Plan is execution-ready for GL-007 only. | Next action: hand off to implementation execution; do not edit source matrix or breakdown.
- 2026-05-10 04:05:06 CEST | Role: Arbiter started | Files inspected since last update: reviewer findings, full draft plan, source row constraints, mandatory sections, scope guard, accepted differences | Decision/blocker: no structural blocker identified so far. Classifying reviewer result into structural blockers, incremental details, and accepted differences. | Next action: write arbiter decision and final execution-ready status if no structural blocker remains.
- 2026-05-10 04:04:30 CEST | Role: Reviewer completed | Files inspected since last update: full draft, mandatory section list, sufficiency review questions, GL-007 evidence notes, adjacent GL-006 contract, source/breakdown scope guard | Decision/blocker: sufficient as-is; no structural blocker. The plan has exact files, RED/GREEN join regression, supporting validator proof, race/panic command, narrow production change, known-failure interpretation, and explicit GL-012 exclusion. | Next action: Arbiter classification and final status.
- 2026-05-10 04:04:07 CEST | Role: Reviewer started | Files inspected since last update: full draft mandatory sections, sufficiency review questions, evidence notes, gate contract, scope guard | Decision/blocker: no blocker yet. Reviewing whether the plan is execution-safe as drafted and whether any missing test/gate/scope issue is structural. | Next action: record reviewer findings and sufficiency classification.
- 2026-05-10 04:03:42 CEST | Role: Planner completed | Files inspected since last update: draft mandatory sections and evidence notes | Decision/blocker: no blocker. Draft is code-plus-tests, chooses upfront nil-config rejection, defines RED/GREEN join regression, supporting validator proof, exact gates, closure bar, scope guard, known-failure interpretation, and dependency impact. | Next action: Reviewer sufficiency pass.

## Execution Progress

- 2026-05-10 04:07:47 CEST | Phase: Controller contract extraction | Files inspected/touched: GL-007 plan, scoped git status/diff, Codex CLI help | Command: `git status --short -- ...` and scoped `git diff -- ...` completed | Decision/blocker: contract is execution-ready and Codex CLI spawning is available; existing dirty work is present in scoped Go files and inspection-only adjacent files, so edits must stay surgical. | Next action: spawn Executor agent with GL-007-only instructions.
- 2026-05-10 04:08:38 CEST | Phase: Executor spawn retry | Files inspected/touched: GL-007 plan | Command: first `codex exec` spawn failed before child work because `--ask-for-approval` was passed to the subcommand instead of the top-level CLI | Decision/blocker: no repo changes from child; retry with corrected top-level CLI option. | Next action: spawn Executor agent again.
- 2026-05-10 04:09:12 CEST | Phase: Executor started | Files inspected/touched: GL-007 plan, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, scoped dirty status/diff including `go-mknoon/node/node.go` and `go-mknoon/node/pubsub_delivery_test.go` | Command: `git status --short -- ...` and scoped `git diff -- ...` completed | Decision/blocker: prior dirty GL-001..GL-006 work exists in scoped Go files; no blocker. | Next action: add only GL-007 tests.
- 2026-05-10 04:10:35 CEST | Phase: Executor tests added | Files inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: none | Decision/blocker: added `TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState` and `TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007`; production guard not yet applied. | Next action: run RED join regression.
- 2026-05-10 04:10:54 CEST | Phase: RED result | Files inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$' -count=1)` exited 1 | Decision/blocker: expected RED; `JoinGroupTopic` accepted nil config and test failed at `expected nil config join to fail`. | Next action: run validator proof before guard.
- 2026-05-10 04:11:00 CEST | Phase: Supporting validator proof | Files inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 0.336s` | Decision/blocker: pre-guard GREEN is expected supporting proof only. | Next action: add nil-config guard.
- 2026-05-10 04:11:15 CEST | Phase: Production guard applied | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` completed | Decision/blocker: added only `missing group config` guard after nil-key guard and before topic/validator/subscription/map writes. | Next action: run GREEN commands.
- 2026-05-10 04:11:28 CEST | Phase: GREEN result | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 0.450s` | Decision/blocker: direct join regression closed. | Next action: rerun validator proof.
- 2026-05-10 04:11:32 CEST | Phase: GREEN result | Files inspected/touched: `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 0.337s` | Decision/blocker: row-owned validator proof remains GREEN. | Next action: run race/panic detector.
- 2026-05-10 04:11:45 CEST | Phase: Race/panic proof | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test -race ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$|^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 1.571s` | Decision/blocker: no row-owned race/panic issue. | Next action: run row Go regression sweep.
- 2026-05-10 04:11:55 CEST | Phase: Go row sweep | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 4.318s` | Decision/blocker: adjacent Go join/leave/config/key/stop/recovery sweep is GREEN. | Next action: run startup rejoin smoke.
- 2026-05-10 04:12:20 CEST | Phase: Flutter startup rejoin smoke | Files inspected/touched: none beyond required command | Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart` passed, `00:00 +3: All tests passed!` | Decision/blocker: required Flutter smoke is GREEN; dependency resolution printed package-update notices only. | Next action: run diff hygiene.
- 2026-05-10 04:12:29 CEST | Phase: Diff hygiene | Files inspected/touched: full worktree diff whitespace check | Command: `git diff --check` passed with no output | Decision/blocker: no whitespace errors. | Next action: finalize Executor summary.
- 2026-05-10 04:12:29 CEST | Phase: Executor completed | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, this GL-007 plan execution progress | Command: required GL-007 RED/GREEN, race, row Go sweep, Flutter smoke, and diff hygiene completed | Decision/blocker: GL-007 implementation complete; no untriaged failures and no full groups gate required because Dart/Flutter behavior was not edited. | Next action: QA verify final diff scope and guard placement.
- 2026-05-10 04:14:12 CEST | Phase: QA Reviewer spawn | Files inspected/touched: this GL-007 plan execution progress | Command: Executor child completed with GL-007 code/test/doc delta and required command evidence | Decision/blocker: no executor blocker. | Next action: spawn separate QA Reviewer agent for sufficiency review.
- 2026-05-10 04:16:12 CEST | Phase: QA Reviewer started | Files inspected/touched: GL-007 plan, scoped worktree status/diff, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | Command: `git status --short`, `git diff --name-only`, scoped `git diff -- ...`, `nl -ba ...`, and `rg ...` inspections completed | Decision/blocker: reviewing strict GL-007 sufficiency; broad unrelated dirty work remains present and is treated as pre-existing unless tied to this session. | Next action: classify blocking issues and gate sufficiency.
- 2026-05-10 04:16:12 CEST | Phase: QA Reviewer completed | Files inspected/touched: this GL-007 plan execution progress | Command: strict scope, guard-order, row-owned test, recorded RED/GREEN/race/sweep/smoke/diff-hygiene evidence, and full-groups-gate requirement review completed | Decision/blocker: QA verdict accepted. No blocking issues found; guard is before topic/validator/join/subscription/map writes/goroutines; row-owned tests cover rejected nil config state, nil key info lookup, publish-after-rejection, and nil-config validator rejection; required evidence is recorded. A full groups gate is not required because GL-007 final scoped work is limited to Go guard/tests and the plan progress update. | Next action: report accepted QA sufficiency verdict.
- 2026-05-10 04:17:05 CEST | Phase: Final controller verdict | Files inspected/touched: this GL-007 plan execution progress | Command: spawned Executor and spawned QA Reviewer completed sequentially | Decision/blocker: final verdict accepted; no blocking issues or non-blocking follow-ups remain. | Next action: report final execution verdict.

## Evidence Collector Notes

- Source matrix row `GL-007` requires `JoinGroupTopic` with valid key and nil config to avoid panic, return a clear group-config-missing result, and prevent publish or validator acceptance.
- Breakdown row `GL-007` classifies the row as `needs_code_and_tests` and `implementation-ready`; adjacent GL-001..GL-006 rows are closed and must not be reopened.
- Current `JoinGroupTopic` rejects nil PubSub, duplicate joins, and nil `keyInfo`, then registers a validator, joins/subscribes, stores `n.groupConfigs[groupId] = config`, stores key info, and starts subscription/discovery goroutines. There is no nil-config guard before the store.
- `PublishGroupMessage` treats map presence as joined state, then calls `isAllowedWriter(config, senderPeerId)`. `isAllowedWriter` calls `findMember`, and `findMember` iterates `config.Members`; a nil config can panic.
- `PublishGroupReaction` calls `findMember(config, senderPeerId)` after map-presence checks and has the same nil-config risk.
- Production `groupTopicValidator` checks only whether `groupConfigs[groupId]` exists before calling `findMember(config, env.SenderId)`, so a nil config map value can panic. The pure `validateGroupEnvelope` test helper already treats `config == nil` as `reject:unknown_group`.
- Discovery helpers that consume `groupConfigs` include mixed nil handling: one discovery path guards `config != nil`, but `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, and `countConnectedGroupMembers` dereference config after only a map-presence check. Rejecting nil config before join avoids starting these loops with nil state.
- Existing GL-006 code/test evidence selected upfront nil-key join rejection because a non-sendable joined state would require broader lifecycle semantics. The same reasoning applies more strongly to nil config because config is consumed by publish, reaction, validation, and discovery.
- `UpdateGroupConfig(groupId, nil)` remains a separate GL-012 source row and should not be fixed in GL-007.
- Current worktree has broad unrelated dirty work, including adjacent GL code/tests. GL-007 execution must preserve it and limit edits to `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and this plan file unless executor evidence proves otherwise.

## real scope

Own exactly source row `GL-007`: `JoinGroupTopic(groupId, nil, validKeyInfo)` must be explicit and non-dangerous.

Selected current-architecture contract: upfront join rejection. A nil config must be rejected before topic name creation, validator registration, topic join, subscription, local map writes, subscription handler startup, or discovery loop startup.

This session may edit only:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- this GL-007 plan file during execution progress/QA updates

Inspection-only unless direct executor evidence disproves the plan:

- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/node.go`

Do not edit the source matrix or session breakdown during GL-007 implementation.

## closure bar

GL-007 is good enough when:

- `JoinGroupTopic` rejects nil config with a clear error containing `missing group config` before any live pubsub topic/validator/subscription/local group state is created.
- The rejected group has no entries in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx`.
- `GetGroupKeyInfo(groupId)` returns nil after the rejected join.
- `PublishGroupMessage` after the rejected join does not panic, returns `group not joined`, and returns empty message id plus peer count `0`.
- A row-owned validator helper proof shows a nil config rejects the envelope as `reject:unknown_group` and does not accept the message.
- Direct GL-007 tests run RED before the production guard for the expected reason, then GREEN after the guard.
- Required direct Go, race/panic, startup rejoin smoke, and diff hygiene commands pass or any failure is explicitly classified before closure.

## source of truth

1. Current code and tests in `go-mknoon/node` win over stale prose.
2. Source matrix row `GL-007` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` defines the row behavior.
3. Session breakdown row `GL-007` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` provides planning context and the code-plus-tests disposition.
4. `Test-Flight-Improv/test-gate-definitions.md` defines named gate intent; if it conflicts with `scripts/run_test_gates.sh`, the script wins.
5. The accepted GL-006 plan/test evidence is adjacent context only: it establishes the nil-key upfront rejection pattern but must not be reopened.
6. This GL-007 plan is the active execution contract once `Status: execution-ready` is written.

## session classification

`implementation-ready`

Disposition: code plus tests. Current code accepts nil config at join time and stores it as joined local state, while later group paths dereference config.

## exact problem statement

`JoinGroupTopic` currently validates nil PubSub, duplicate join, and nil `keyInfo`, but not nil `config`. With a valid key and nil config, it can register a validator, join and subscribe to the group topic, store `n.groupConfigs[groupId] = nil`, store a key, and start subscription/discovery goroutines.

That nil map value makes the group look joined even though these downstream paths require a real config:

- `PublishGroupMessage` checks only map presence, then calls `isAllowedWriter(config, senderPeerId)`.
- `PublishGroupReaction` checks only map presence, then calls `findMember(config, senderPeerId)`.
- `groupTopicValidator` checks only map presence, then calls `findMember(config, env.SenderId)`.
- discovery helpers such as `dialKnownGroupMembers`, `dialKnownGroupMembersDirectOnly`, and `countConnectedGroupMembers` can dereference `config.Members` after only a map-presence check.

User-visible behavior must improve from possible panic or silent joined-but-unusable state to explicit nil-config rejection with no published or accepted message. Normal successful joins, duplicate-join behavior, nil-key behavior, join/subscribe cleanup, key rotation, delivery, Dart/Flutter bridge behavior, and `UpdateGroupConfig(nil)` must stay unchanged.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
  - `JoinGroupTopic`
  - `PublishGroupMessage`
  - `PublishGroupReaction`
  - `groupTopicValidator`
  - `isAllowedWriter`
  - `findMember`
  - group discovery helpers that read `groupConfigs`
- `go-mknoon/node/pubsub_test.go`
  - adjacent GL-001..GL-006 tests
  - pure `validateGroupEnvelope` helper and validator tests
  - `findMember` / `isAllowedWriter` tests
- `go-mknoon/node/pubsub_delivery_test.go`
  - inspect only if direct local tests cannot prove no publish/acceptance.
- `go-mknoon/node/node.go`
  - inspect only if a private test seam becomes strictly necessary; none is expected.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`
  - gate source of truth for the groups gate and completeness rule.

## existing tests covering this area

- `TestJoinGroupTopic_FailsWithoutPubSub` covers GL-001 nil PubSub rejection and no attempted group state.
- `TestJoinGroupTopic_DuplicateJoinPreservesExistingState` and `TestJoinGroupTopic_DuplicateJoinPreservesDelivery` cover GL-002 duplicate join state/delivery preservation.
- `TestJoinGroupTopic_JoinFailureUnregistersValidatorAndAllowsRetry` covers GL-003 join failure cleanup after validator registration.
- `TestJoinGroupTopic_SubscribeFailureUnregistersValidatorClosesTopicAndAllowsRetry` covers GL-004 subscribe failure cleanup.
- `TestJoinGroupTopic_SuccessStoresAtomicStateAndSupportsImmediateKeyInfoAndPublish` covers GL-005 successful join state and immediate publish.
- `TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState` and `TestGroupTopicValidator_NilKeyRejectsNoKeyAndDecryptReportsMissingKey` cover GL-006 nil-key rejection and inbound nil-key helper behavior.
- `TestGroupTopicValidator_UnknownGroup` already proves the pure helper returns `reject:unknown_group` for nil config, but it is generic and not row-owned for GL-007.
- Existing `findMember` and `isAllowedWriter` tests cover valid configs and missing members; they do not cover nil config because GL-007 should reject nil config before those helpers are reachable through join.

Missing GL-007 coverage: no row-owned test proves `JoinGroupTopic` rejects nil config before local state is stored, and no row-owned test ties publish-after-rejection plus nil-config validator rejection to GL-007.

## regression/tests to add first

Add `TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState` in `go-mknoon/node/pubsub_test.go`, adjacent to `TestJoinGroupTopic_RejectsNilKeyInfoAndLeavesNoGroupState`.

Test contract:

1. Start a local `Node` with pubsub initialized.
2. Generate a valid group key and valid sender signing key pair.
3. Call `JoinGroupTopic(groupId, nil, &GroupKeyInfo{Key: groupKey, KeyEpoch: 1})`.
4. Before the production fix, record RED because the call returns nil instead of a missing-config error.
5. After the fix, assert the error contains `missing group config`.
6. Assert no entries exist for the group in `groupTopics`, `groupSubs`, `groupConfigs`, `groupKeys`, `groupSubCtx`, or `groupDiscoveryCtx`.
7. Assert `GetGroupKeyInfo(groupId)` returns nil.
8. Wrap `PublishGroupMessage` in a `recover` guard, then call it for the rejected group. Assert no panic, error contains `group not joined`, message id is empty, and peer count is `0`.

Add `TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007` in `go-mknoon/node/pubsub_test.go`.

Test contract:

1. Build a valid encrypted group envelope with generated sender keys and group key.
2. Call `validateGroupEnvelope(envelopeJSON, groupId, nil, keyInfo)`.
3. Assert the result is `reject:unknown_group`.

The validator helper proof may already pass before the production guard; that is acceptable as supporting evidence only. The required RED/GREEN driver is the `JoinGroupTopic` nil-config regression.

## step-by-step implementation plan

1. Re-check scoped dirty status/diff for `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/node.go`, and `go-mknoon/node/pubsub_delivery_test.go`. Preserve unrelated user-owned changes.
2. Add only the GL-007 row-owned tests described above.
3. Run the direct join regression before production code changes:

   ```bash
   (cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$' -count=1)
   ```

   Expected RED: `JoinGroupTopic` accepts nil config and the test fails at the expected missing-config error assertion. If the test already passes, stop and inspect whether user-owned changes already fixed GL-007.

4. Run the validator helper proof and record whether it is already GREEN:

   ```bash
   (cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)
   ```

5. In `go-mknoon/node/pubsub.go`, add the minimal nil-config guard in `JoinGroupTopic` after the existing nil PubSub, duplicate-join, and nil-key checks, and before `topicName`, `RegisterTopicValidator`, `pubsub.Join`, subscription, or any map write:

   ```go
   if config == nil {
       return fmt.Errorf("missing group config for group %s", groupId)
   }
   ```

   Keep the existing nil-key guard order unchanged so GL-006 behavior remains stable.

6. Do not change `findMember`, `isAllowedWriter`, `PublishGroupMessage`, `PublishGroupReaction`, `groupTopicValidator`, discovery helpers, `UpdateGroupConfig`, `node.go`, bridge code, Dart/Flutter code, or delivery tests unless the direct GL-007 tests prove the upfront guard is insufficient.
7. Rerun the direct GL-007 join regression and validator helper proof; both must pass.
8. Run the row Go command, race/panic command, startup rejoin smoke, and diff hygiene commands listed below.
9. QA must verify final diff scope is limited to GL-007 production/test changes plus this plan's execution progress. Source matrix and breakdown must remain untouched.

Stop and return to planning if the nil-config guard breaks duplicate-join semantics, nil-key semantics, nil-PubSub semantics, successful join state, startup rejoin smoke, or requires changes outside the allowed files.

## risks and edge cases

- Guard placement matters. If the nil-config guard is placed after validator registration or topic join, a failed nil-config join could still leave stale validator/topic state.
- Existing nil-key behavior should remain unchanged. Placing the nil-config guard after the nil-key guard avoids changing GL-006 error priority for a call with both values nil.
- Allowing a non-sendable joined state would require broad guards across publish, reaction, production validator, discovery, rejoin, and Flutter/UI status. That is intentionally rejected for this session.
- `UpdateGroupConfig(groupId, nil)` can still introduce nil config after a valid join. That is GL-012 and must not be fixed under GL-007.
- Discovery goroutines can race with bad local state if nil config is stored. Upfront rejection avoids starting them for this row.
- The worktree has existing dirty changes in the same Go files from adjacent GL work; executor edits must be surgical and must not revert or rewrite unrelated changes.

## exact tests and gates to run

Direct RED/GREEN tests:

```bash
(cd go-mknoon && go test ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$' -count=1)
(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)
```

Race/panic detector for the row-owned tests:

```bash
(cd go-mknoon && go test -race ./node -run '^TestJoinGroupTopic_RejectsNilConfigAndLeavesNoGroupState$|^TestGroupTopicValidator_NilConfigRejectsUnknownGroupForGL007$' -count=1)
```

Row Go regression sweep:

```bash
(cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1)
```

Flutter startup rejoin smoke, matching adjacent GL row practice:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Diff hygiene:

```bash
git diff --check
```

Named gates: no full named gate is required if the final diff is limited to the Go nil-config guard and Go tests. If execution touches Dart/Flutter group send, receive, retry, resume, invite, or announcement behavior, run:

```bash
./scripts/run_test_gates.sh groups
```

If gate definitions or test inventory docs are edited, also run:

```bash
./scripts/run_test_gates.sh completeness-check
```

## known-failure interpretation

No GL-007 known failure is accepted.

The direct join regression must fail before the production guard for the specific reason that `JoinGroupTopic` accepted nil config. If it does not fail, stop and inspect whether existing user-owned changes already fixed GL-007; do not duplicate behavior.

The validator helper proof may pass before production code because the pure helper already has nil-config handling. That pre-existing GREEN does not close GL-007 by itself; the join rejection RED/GREEN remains mandatory.

After the guard, all mandatory commands must pass. If a broader row command fails, classify the failure before any fix as one of: caused by GL-007, pre-existing, flaky, unrelated-but-required, or environment/tooling. Do not hide a new GL-007 failure behind existing dirty-worktree noise.

## done criteria

- `Status: execution-ready` was present before implementation began.
- The selected GL-007 contract is upfront nil-config rejection.
- The row-owned join regression exists in `go-mknoon/node/pubsub_test.go` and records RED/GREEN evidence.
- The row-owned validator helper proof exists in `go-mknoon/node/pubsub_test.go`.
- `JoinGroupTopic` returns a `missing group config` error for nil config before validator registration, topic join, subscription, map writes, or goroutine startup.
- Publish after rejected join is non-panicking and returns `group not joined`, empty message id, and peer count `0`.
- Required commands under `exact tests and gates to run` complete with no untriaged failures.
- Final diff is limited to GL-007 code/tests and this plan's execution-progress updates.
- Source matrix and session breakdown remain unedited.

## scope guard

Do not:

- reopen GL-001 through GL-006;
- fix or test `UpdateGroupConfig(groupId, nil)` under GL-007;
- add a joined/non-sendable group state enum;
- add broad nil guards to `findMember`, `isAllowedWriter`, production validator, publish/reaction, or discovery helpers unless the upfront guard cannot satisfy the row;
- change key rotation, previous-key grace, `UpdateGroupKey`, decrypt semantics, or nil-key behavior;
- change group delivery, live peer discovery cadence, subscription handler behavior, bridge APIs, Dart/Flutter rejoin logic, or UI sendability state;
- add live multi-node delivery tests when the direct local test and validator helper prove the row;
- edit the source matrix or session breakdown.

Overengineering for GL-007 includes broad group state-machine refactors, lifecycle-wide "non-sendable joined" semantics, UI/bridge status changes, or turning GL-012's setter nil-config problem into this session.

## accepted differences / intentionally out of scope

- Accepted difference: the source row allows join rejection or explicit non-sendable state; this plan intentionally chooses join rejection because it is the smallest safe contract supported by current Go code.
- Accepted difference: publish after the rejected join returns `group not joined`, not `missing group config`, because no joined state should exist after the rejection.
- Accepted difference: the pure validator helper returns `reject:unknown_group` for nil config. Do not rename validator diagnostics to `missing_config` unless an existing production contract already requires that wording.
- Accepted difference: no live validator exists after rejected nil-config join, so the row-owned validator proof uses the pure helper rather than forcing a live GossipSub validator path.
- Intentionally out of scope: `UpdateGroupConfig(nil)` remains GL-012.
- Intentionally out of scope: live multi-node delivery proof remains unnecessary unless direct tests reveal a gap.

## dependency impact

Closing GL-007 gives later group lifecycle, startup rejoin, and discovery work a clear invariant: a group successfully joined through `JoinGroupTopic` has non-nil config and non-nil key info at join time.

Later rows can rely on `JoinGroupTopic` rejecting nil config, but they must not assume `UpdateGroupConfig` rejects nil until GL-012 is implemented.

If this plan changes to allow a non-sendable joined state, downstream work touching publish, reaction, validator diagnostics, discovery loops, rejoin, bridge state, Flutter group sendability, and startup recovery must be revisited before closure.

## Reviewer Findings

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none structural. `go-mknoon/node/pubsub_delivery_test.go` and `go-mknoon/node/node.go` are correctly inspection-only unless direct local proof fails. `PublishGroupReaction` does not need a regression because the selected contract prevents joined nil-config state from existing through `JoinGroupTopic`; GL-012 owns setter-injected nil config.

Stale or incorrect assumptions: none found. The plan correctly treats the existing generic `TestGroupTopicValidator_UnknownGroup` helper behavior as useful but not row-owned GL-007 coverage.

Overengineering: none. A row-owned nil-config validator helper test is mildly redundant with the generic unknown-group helper test, but acceptable because the source row explicitly asks for validator proof.

Decomposition: enough to minimize hallucination. One RED/GREEN join regression drives the production guard; one helper proof covers non-acceptance without live topic setup.

Minimum needed to make the plan sufficient: already present. Executor must preserve guard ordering, record the expected RED, and avoid absorbing GL-012.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- No `PublishGroupReaction` regression is required for GL-007 because upfront join rejection prevents nil-config joined state through `JoinGroupTopic`.
- No live multi-node delivery test is required unless the direct local join regression or validator helper proof fails to prove the row.
- No production validator diagnostic rename is required; `reject:unknown_group` remains the accepted helper result for nil config.

Accepted differences:

- Upfront join rejection is selected instead of explicit non-sendable joined state.
- Publish after rejected join returns `group not joined` rather than `missing group config`.
- `UpdateGroupConfig(nil)` remains separate GL-012 work even though it can still create nil config after a valid join.

Final arbiter verdict: execution-ready for GL-007 only. The stop rule applies because the reviewer found no structural blockers, so no second review loop is needed.
