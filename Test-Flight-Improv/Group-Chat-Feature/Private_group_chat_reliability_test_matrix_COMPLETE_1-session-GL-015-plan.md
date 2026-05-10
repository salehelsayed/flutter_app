Status: execution-ready

# GL-015 Same-Epoch Group Key Mismatch Plan

Session source:
- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- Breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- Row: `GL-015 | UpdateGroupKey same epoch with different material is rejected explicitly | G has epoch 3 key K1; caller supplies epoch 3 key K2. | 1. UpdateGroupKey(G, K2/E3). 2. Publish/decrypt. 3. Inspect diagnostics. | Either same-epoch key mismatch is rejected with an alert or ignored deterministically; local state never becomes split-brain. | P0 | Open | Required | Required | N/A | N/A | N/A | Same epoch/different key is dangerous during re-add races.`

## Planning Progress

- `2026-05-10 07:07:09 CEST` - Arbiter completed. Files inspected since last update: reviewer findings, full draft plan, exact tests/gates. Decision/blocker: no structural blockers; plan is execution-ready as tests-only deterministic-ignore proof with a narrow Go fallback only if the regression fails. Next action: execute the GL-015 plan in a separate implementation phase without editing source matrix, session breakdown, or row closure docs.
- `2026-05-10 07:06:37 CEST` - Arbiter started. Files inspected since last update: reviewer findings and full draft plan. Decision/blocker: reviewer found the plan sufficient as tests-only; no structural blocker identified so far. Next action: classify stale breakdown/code+tests disposition, conditional groups gate, and diagnostic non-goal.
- `2026-05-10 07:06:37 CEST` - Reviewer completed. Files inspected since last update: full plan, mandatory sections, test/gate commands, source-row expected result, current app diagnostic contracts. Decision/blocker: sufficient as-is; no explicit diagnostics required, and no Dart/Flutter production edits are justified. Next action: Arbiter pass.
- `2026-05-10 07:05:07 CEST` - Reviewer started. Files inspected since last update: draft plan content. Decision/blocker: draft classifies GL-015 as tests-only unless the row-owned regression disproves current deterministic-ignore behavior. Next action: review for missing files, gates, scope drift, stale assumptions, and whether explicit diagnostics are actually required.
- `2026-05-10 07:05:07 CEST` - Planner completed. Files inspected since last update: evidence summary and gate contracts. Decision/blocker: plan is implementation-ready/tests-only with a narrow `TestGL015...` delivery regression; no source/doc closure edits are part of execution. Next action: Reviewer sufficiency pass.

## Execution Progress

- `2026-05-10 07:09:07 CEST` - Phase: contract extracted. Files inspected/touched: this GL-015 plan, current git status, `go-mknoon/node/pubsub_key_rotation_grace_test.go` diff/search context. Command: none. Decision/blocker: execution scope is one row-owned Go regression plus this progress section; production fallback only if the regression proves deterministic ignore is broken. Next action: spawn Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-10 07:09:24 CEST` - Phase: Executor spawn starting. Files inspected/touched: this GL-015 plan progress section. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: no blocker; child receives narrow write scope and required commands. Next action: Executor adds the row-owned regression, runs required evidence, and records results here.
- `2026-05-10 07:10:47 CEST` - Phase: Executor running. Files inspected/touched: this GL-015 plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go`, local dirty git status. Command: none. Decision/blocker: current `UpdateGroupKey` already ignores same-or-lower epochs; proceeding with tests-only GL-015 delivery proof unless focused regression fails. Next action: add `TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery`.
- `2026-05-10 07:13:24 CEST` - Phase: Executor implementation completed. Files inspected/touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this GL-015 plan progress section. Command: `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go`. Decision/blocker: added `TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery` using generated epoch-2 key, epoch-3 K1, conflicting epoch-3 K2, two collector-backed local nodes, unchanged key snapshots before/after K2, epoch-3 delivery assertions, no receiver `group:decryption_failed`, and unchanged receiver key info after delivery. No production code changed by this Executor. Next action: evidence commands.
- `2026-05-10 07:13:24 CEST` - Phase: focused GL-015 evidence passed. Files inspected/touched: none beyond test execution. Command: `cd go-mknoon && go test ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1`. Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 1.083s`; current production deterministic-ignore behavior satisfies the row, so production fallback was not used. Next action: race evidence.
- `2026-05-10 07:13:24 CEST` - Phase: focused GL-015 race evidence passed. Files inspected/touched: none beyond test execution. Command: `cd go-mknoon && go test -race ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1`. Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 2.119s`. Next action: adjacent key/decrypt sweep.
- `2026-05-10 07:13:24 CEST` - Phase: adjacent key/decrypt sweep passed. Files inspected/touched: none beyond test execution. Command: `cd go-mknoon && go test ./node -run 'Test(UpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)|GL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery|GL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery|HandleGroupSubscription_EmitsDecryptionFailedEvent)' -count=1`. Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 3.072s`. Next action: GL evidence-key Go sweep.
- `2026-05-10 07:13:24 CEST` - Phase: GL evidence-key Go sweep passed. Files inspected/touched: none beyond test execution. Command: `cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1`. Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 17.646s`. Next action: Flutter startup rejoin smoke.
- `2026-05-10 07:13:24 CEST` - Phase: Flutter startup rejoin smoke passed. Files inspected/touched: none beyond test execution. Command: `flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart`. Decision/blocker: PASS, `00:00 +3: All tests passed!`. Next action: diff hygiene.
- `2026-05-10 07:13:24 CEST` - Phase: diff hygiene passed and Executor handoff. Files inspected/touched: none beyond diff check. Command: `git diff --check`. Decision/blocker: PASS with no output. Conditional `./scripts/run_test_gates.sh groups` was skipped because this Executor made no production behavior change. Next action: QA Reviewer should inspect the landed GL-015 test and recorded evidence.
- `2026-05-10 07:14:41 CEST` - Phase: QA Reviewer spawn starting. Files inspected/touched: this GL-015 plan progress section and Executor handoff `/tmp/gl015-executor-final.txt`. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app`. Decision/blocker: Executor completed with row-owned test, required PASS evidence, and no production edits. Next action: QA Reviewer checks scope, assertions, required commands, and residual risk without fixing code.
- `2026-05-10 07:15:41 CEST` - Phase: QA Reviewer started. Files inspected/touched: this GL-015 plan, Executor handoff `/tmp/gl015-executor-final.txt`, current dirty status. Command: none. Decision/blocker: QA scope is review-only with write access limited to this progress section. Next action: inspect GL-015 test assertions, surrounding key helpers, diff scope, and recorded PASS evidence.
- `2026-05-10 07:17:49 CEST` - Phase: QA Reviewer completed. Files inspected/touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub.go`, this progress section, Executor handoff. Commands: `cd go-mknoon && go test ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1`; `cd go-mknoon && go test -race ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1`; `git diff --check`. Decision/blocker: no blocking issues; GL-015 row test proves deterministic ignore plus epoch-3 delivery, recorded Executor PASS evidence covers remaining required sweeps, and no GL-015 production/source-matrix/breakdown/final-verdict scope violation was found. Next action: controller may accept GL-015 execution.
- `2026-05-10 07:18:32 CEST` - Phase: final execution verdict written. Files inspected/touched: this GL-015 plan progress section, Executor and QA handoffs. Command: none. Decision/blocker: accepted; no blocking issues or non-blocking follow-ups remain, production code was not changed by GL-015, and source matrix/session breakdown/final rollout verdict remain untouched. Next action: stop GL-015 execution.

## real scope

GL-015 owns only the Go node boundary where `Node.UpdateGroupKey(groupId, keyInfo)` receives key material for the same epoch as the current local group key.

Planned execution is tests-only unless the new row-owned regression proves current disk behavior is not deterministic. The intended regression belongs in `go-mknoon/node/pubsub_key_rotation_grace_test.go` and should prove an epoch-3 current key `K1` survives a same-epoch `K2` update, subsequent publish/decrypt still uses `K1`, `GetGroupKeyInfo` remains unchanged before and after delivery, and no receiver-side `group:decryption_failed` or split-brain visible message occurs.

No Dart/Flutter production edits are planned. No source matrix, session breakdown, closure ledger, or row status updates are part of execution.

## closure bar

GL-015 is good enough when a row-named Go regression proves:

- both sender and receiver have current epoch 3 key `K1` before the conflicting update
- applying `UpdateGroupKey(G, K2/E3)` to both nodes leaves current key, current epoch, previous key, previous epoch, and grace deadline unchanged
- a message published after the conflicting update is encrypted/signed with epoch 3 and decrypts on the receiver with `K1`
- the receiver emits the expected `group_message:received` event and does not emit `group:decryption_failed` for that delivery
- final `GetGroupKeyInfo` still matches the pre-conflict snapshot

Explicit local diagnostics are not required for closure because the source row allows deterministic ignore as an alternative to explicit rejection.

## source of truth

Current code and tests win over stale planning prose.

Authoritative docs and evidence:

- Source row GL-015 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- GL evidence key, row inventory, and ordered-session entry in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `go-mknoon/node/pubsub.go::UpdateGroupKey`, `GetGroupKeyInfo`, `PublishGroupMessage`, `decryptGroupEnvelopePayload`, and `emitGroupDecryptionFailed`
- Existing adjacent tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go` and `go-mknoon/node/pubsub_decryption_failure_test.go`
- `Test-Flight-Improv/test-gate-definitions.md` for named gate commands
- GEK-001/Report 94 evidence only for app-layer conflict policy; it does not close GL-015 by itself

If the source row title asks for explicit rejection but the expected-result cell allows deterministic ignore, the expected-result cell controls.

## session classification

`implementation-ready`

Execution classification: tests-only deterministic-ignore proof, with a narrow Go production fallback only if the new GL-015 regression fails for current key mutation or delivery breakage.

## exact problem statement

Same-epoch, different-material group keys are dangerous because two callers can race during re-add or recovery and leave local state split between `K1/E3` and `K2/E3`. Current disk evidence shows `UpdateGroupKey` ignores `keyInfo.KeyEpoch <= current.KeyEpoch`, so the likely production behavior is already deterministic no-op. The missing row-owned proof is that this no-op remains safe through the actual publish/decrypt path under GL-015's epoch-3 conditions.

User-visible behavior that must stay correct: recipients must not lose readable current-epoch group messages, must not silently move to different key material for the same epoch, and must not produce a fake received message when decryption fails.

Behavior that must stay unchanged: higher-epoch updates still rotate to the new key and preserve previous-key grace state; older-epoch updates remain ignored; existing receive-side wrong-key diagnostics still emit `group:decryption_failed`.

## files and repos to inspect next

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_delivery_test.go` only if delivery helper reuse is needed
- `go-mknoon/node/group_security_harness_test.go` only if helper reuse is needed
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GL-015-plan.md` for execution status only

Do not inspect or edit Dart/Flutter production files unless the Go regression unexpectedly proves the row cannot be satisfied at the Go boundary.

## existing tests covering this area

- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial` proves same-epoch different material does not replace the current key, previous key, previous epoch, or grace deadline. It uses simple string keys and does not publish/decrypt.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` proves the sibling older-epoch case with real generated keys, two nodes, epoch-3 delivery, no decryption failure, and unchanged receiver key state.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEvent` proves true same-epoch split material at receive time emits `group:decryption_failed` and suppresses `group_message:received`.
- `test/features/groups/application/group_key_update_listener_test.dart::conflicting same-generation key updates keep first accepted material` proves the Flutter direct key-update listener does not promote conflicting same-generation material or call `group:updateKey` a second time.

Verified during planning:

```bash
cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial' -count=1
cd go-mknoon && go test ./node -list 'Test(GL015|GL014|UpdateGroupKey)'
```

The focused same-epoch Go test passed on current disk; the list command showed no GL-015 row-named test yet.

## regression/tests to add first

Add `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery`.

The test should:

- generate real group keys for epoch 2, epoch 3 `K1`, and conflicting epoch 3 `K2`
- start two local nodes with event collectors
- join both nodes at epoch 2, then update both to epoch 3 `K1`
- snapshot `GetGroupKeyInfo` for both nodes, including current key/epoch, previous key/epoch, and grace deadline
- call `UpdateGroupKey(groupId, &GroupKeyInfo{Key: K2, KeyEpoch: 3})` on both nodes
- assert both snapshots are unchanged
- connect the nodes, publish a message from the sender, and wait for the receiver's `group_message:received`
- assert received `groupId`, `senderId`, `messageId`, `text`, and `keyEpoch == 3`
- assert no `group:decryption_failed` appears in receiver events after the publish baseline
- assert receiver `GetGroupKeyInfo` still equals the pre-conflict snapshot after delivery

If this test passes immediately on current production code, do not edit production code.

## step-by-step implementation plan

1. Record `git status --short` before editing and confirm only the GL-015 test file will be touched during execution.
2. Add the row-named test above in `go-mknoon/node/pubsub_key_rotation_grace_test.go`, reusing existing helpers from GL-014 where practical.
3. Run the focused GL-015 command. If it passes on current code, classify execution as tests-only and skip production edits.
4. If the test fails because `UpdateGroupKey` replaces same-epoch material or changes previous-key grace state, make the smallest Go-only fix in `go-mknoon/node/pubsub.go::UpdateGroupKey` to preserve the no-op for same-or-lower epochs. Do not add a new diagnostic event unless deterministic ignore cannot be proven.
5. If the test fails only because delivery helpers are flaky or under-waited, fix the test setup/waiting logic without changing production behavior.
6. Run the exact gates below.
7. Leave source matrix, session breakdown, and row closure untouched. Closure is a later phase.

## risks and edge cases

- Same epoch with different material must not reset `PrevKey`, `PrevKeyEpoch`, or `GraceDeadline`; resetting grace state would weaken adjacent GL-014/previous-epoch behavior.
- A sender and receiver could both receive the same bad `K2/E3` update. The regression applies it to both nodes to prove they still converge on `K1/E3`.
- A true split-brain receiver with different same-epoch material is already covered by receive-side decryption diagnostics; GL-015 must not create that state via `UpdateGroupKey`.
- Delivery tests use local pubsub goroutines and peer discovery waits; race detection is required for the new row test.
- The dirty tree contains unrelated edits, so execution must avoid broad cleanup, formatting, or doc closure churn.

## exact tests and gates to run

Focused row regression:

```bash
cd go-mknoon && go test ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1
```

Focused race regression because the row-owned test uses local nodes, pubsub delivery, and goroutines:

```bash
cd go-mknoon && go test -race ./node -run 'TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery' -count=1
```

Adjacent key/decrypt sweep:

```bash
cd go-mknoon && go test ./node -run 'Test(UpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)|GL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery|GL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery|HandleGroupSubscription_EmitsDecryptionFailedEvent)' -count=1
```

Row Go sweep from the GL evidence key:

```bash
cd go-mknoon && go test ./node -run 'JoinGroupTopic|LeaveGroupTopic|UpdateGroupConfig|UpdateGroupKey|StopNode|GroupRecovery' -count=1
```

Flutter startup rejoin smoke:

```bash
flutter test test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Diff hygiene:

```bash
git diff --check
```

Conditional only if production behavior changes beyond adding the test:

```bash
./scripts/run_test_gates.sh groups
```

Conditional only if Dart/Flutter key-update code is touched despite this plan's guard:

```bash
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'conflicting same-generation key updates keep first accepted material'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart
```

## known-failure interpretation

Any failure in the new `TestGL015...` regression is a GL-015 blocker.

Any failure in existing `UpdateGroupKey`, GL-014, or `HandleGroupSubscription_EmitsDecryptionFailedEvent` tests is a GL-015 blocker unless a clean pre-existing failure is demonstrated before GL-015 edits.

If the GL evidence-key row sweep or Flutter startup rejoin smoke fails in unrelated dirty files, record the exact failure and compare against a pre-edit rerun where feasible. Do not classify unrelated dirty-tree failures as GL-015 regressions, but do not close execution unless the focused GL-015 and adjacent Go commands pass.

## done criteria

- A row-named GL-015 Go test exists and proves deterministic ignore plus epoch-3 publish/decrypt safety.
- No production code changed unless the new test required a narrow `UpdateGroupKey` fix.
- Focused normal and race GL-015 commands pass.
- Adjacent key/decrypt sweep passes.
- Row Go sweep and Flutter startup rejoin smoke are run and recorded.
- `git diff --check` passes.
- `./scripts/run_test_gates.sh groups` is run only if production behavior changes.
- Source matrix, session breakdown, and row status remain unchanged during execution.

## scope guard

Do not implement broad key distribution, member re-add, invite, durable replay, pending-key repair, bridge payload, SQL, or Flutter UI changes for GL-015.

Do not add a new local `UpdateGroupKey` diagnostic event merely because the row title says "rejected explicitly"; deterministic ignore is explicitly allowed by the expected-result cell.

Do not change higher-epoch rotation semantics, previous-key grace behavior, receive-side wrong-key diagnostics, or `group:decryption_failed` event fields.

Do not close GL-015, update the source matrix, update the session breakdown, or write a final rollout verdict in this execution.

## accepted differences / intentionally out of scope

Flutter and Go have different ownership here. Flutter's direct key-update listener owns validated P2P key-update acceptance and persistence conflict policy. Go owns active pubsub encryption/decryption key state. GL-015 should prove the Go boundary does not split local active key state; it should not reopen app-layer GEK-001 work.

Explicit local no-op diagnostics are intentionally out of scope because current bridge diagnostic contracts route receive/decrypt/validation failures, not local `UpdateGroupKey` no-op alerts, and the source row accepts deterministic ignore.

## dependency impact

Closing GL-015 later will give GL/GK follow-up rows a stable same-epoch conflict baseline: same-or-lower epoch `UpdateGroupKey` calls must not change active local key state.

If the new test unexpectedly requires production code, later GL rows touching concurrent update or stop/rejoin behavior should re-run their key-state assumptions against the changed `UpdateGroupKey` behavior.

If the plan changes to require explicit diagnostics, bridge diagnostic allowlists, Go event fields, and Flutter diagnostic tests would become dependencies; this plan currently avoids that broader contract.

## reviewer findings

- Sufficiency: sufficient as-is.
- Missing files/tests/gates: none. The row-owned `TestGL015...` regression fills the exact gap left by the existing state-only same-epoch test. The focused race command is required because the regression uses local pubsub delivery. The groups named gate is correctly conditional on production behavior changes.
- Stale or incorrect assumptions: the breakdown's generic `needs_code_and_tests` disposition is stale for current disk if the new regression passes; current `UpdateGroupKey` already ignores same-or-lower epochs. The source row expected result allows deterministic ignore, so explicit alerting is not mandatory.
- Overengineering: adding a new local `UpdateGroupKey` diagnostic event would be overengineering unless deterministic ignore fails. It would require bridge allowlist and Flutter diagnostic contract work outside the row's minimum safe closure.
- Decomposition: the plan is narrow enough for execution. It names one test file, one row-owned test, one production fallback seam, and explicit stop points.
- Minimum needed: add the GL-015 delivery regression and run the listed gates.

## arbiter decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details intentionally deferred:

- Exact helper extraction inside `go-mknoon/node/pubsub_key_rotation_grace_test.go` can be decided during implementation, as long as the row-owned assertions stay explicit.
- The groups named gate remains conditional; it should run only if execution changes production behavior rather than adding the planned test.

Accepted differences intentionally left unchanged:

- Deterministic ignore is accepted instead of a new explicit local `UpdateGroupKey` diagnostic because the source expected result permits either outcome.
- Flutter app-layer same-generation conflict policy remains GEK-001-owned evidence and should not be reopened for GL-015.
- Receive-side wrong-key diagnostics remain `group:decryption_failed`; GL-015 does not add or rename diagnostic event fields.

Why safe to implement now: current disk evidence shows `UpdateGroupKey` already ignores same-or-lower epochs and the existing same-epoch state-only test passes. The plan fills only the missing row proof: epoch-3 same-epoch conflicting material must not change active key state and must not break subsequent publish/decrypt.
