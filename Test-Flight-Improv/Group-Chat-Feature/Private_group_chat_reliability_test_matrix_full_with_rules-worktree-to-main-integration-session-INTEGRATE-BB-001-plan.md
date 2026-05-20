Status: execution-ready

# INTEGRATE-BB-001 Minimal Integration Contract Plan

## Planning Progress

- 2026-05-17: Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blocker remains; this is standard integration mode and the contract is execution-ready. Next action: execute only the BB-001 row-owned integration delta or mark the session skipped if the executor's fresh compare proves it already present.
- 2026-05-17: Reviewer completed. Files inspected since last update: plan draft, current main bridge snippets, worktree bridge snippets, COMPLETE_1 exact-path grep, dirty worktree status. Decision/blocker: sufficient after adding skip/conflict statuses, dirty-worktree note, and focused test contract. Next action: arbiter classification.
- 2026-05-17: Planner completed. Files inspected since last update: source BB-001 plan evidence, worktree source matrix/breakdown/test inventory references, main bridge files. Decision/blocker: main lacks BB-001 adapter indirection and row-named tests; integrate only those missing Go bridge deltas. Next action: reviewer pass.
- 2026-05-17: Evidence Collector completed. Files inspected since last update: integration breakdown, source worktree BB-001 plan, worktree source matrix/breakdown/test inventory, COMPLETE_1 breakdown, main/worktree `go-mknoon/bridge/bridge.go`, main/worktree `go-mknoon/bridge/bridge_test.go`, `git status --short`. Decision/blocker: no exact COMPLETE_1 path overlap found for `go-mknoon/bridge/bridge.go` or `go-mknoon/bridge/bridge_test.go`; main checkout has unrelated dirty files. Next action: draft the integration contract.

## Execution Progress

- 2026-05-17 01:44:11 CEST: Pre-contract extraction status recorded before edits: ` M go-mknoon/bin/testpeer`, ` M info.plist`, ` M pubspec.yaml`, `?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-to-COMPLETE_1-integration-session-breakdown.md`, `?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-001-plan.md`, `?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`. Decision/blocker: unrelated dirty files present; preserve them. Next action: extract contract and compare main/worktree owner deltas.
- 2026-05-17 01:44:11 CEST: Post-contract extraction. Files inspected since last update: current INTEGRATE-BB-001 plan. Decision/blocker: standard integration mode only; allowed code/test files are `go-mknoon/bridge/bridge.go` and `go-mknoon/bridge/bridge_test.go`; allowed doc update is this current plan only per execution prompt. Next action: read BB-001 historical evidence and perform fresh owner-file compare.
- 2026-05-17 01:44:11 CEST: Fresh compare started. Files inspected since last update: historical BB-001 plan, historical worktree `go-mknoon/bridge/bridge.go`, historical worktree `go-mknoon/bridge/bridge_test.go`, main `go-mknoon/bridge/bridge.go`, main `go-mknoon/bridge/bridge_test.go`, COMPLETE_1 breakdown exact-path search, integration breakdown row read-only. Decision/blocker: no COMPLETE_1 exact-path owner overlap found for the two bridge files; no blocker. Next action: classify whether BB-001 is already present or requires a narrow patch.
- 2026-05-17 01:44:11 CEST: Fresh compare completed. Evidence: main still defines `nodeCallbackAdapter` as direct `cb EventCallback`, `Initialize` only passes `&nodeCallbackAdapter{cb: cb}` when `singletonNode == nil`, and main has only `TestNodeCallbackAdapter_ForwardsRelayStateEventUntouched`; historical BB-001 final verdict is `accepted` and worktree has `singletonCallbackAdapter`, `SetCallback`, nil-safe `OnEvent`, repeated-`Initialize` callback refresh, `TestNodeCallbackAdapter_SetCallbackSwapsAndDropsNil`, and `TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents`. Decision/blocker: BB-001 is missing in main and no same-file semantic conflict was found. Next action: patch only the BB-001 adapter/test delta.
- 2026-05-17 01:44:11 CEST: Patching started. Files inspected/touched since last update: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`. Decision/blocker: applying only the BB-001 stable callback adapter, repeated-`Initialize` callback refresh, adapter state restoration in tests, and the two row-owned tests; no blocker. Next action: run `gofmt` and inspect diff.
- 2026-05-17 01:44:11 CEST: Patching completed. Files touched since last update: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`. Command: `gofmt -w go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go`. Diff inspection shows only BB-001 callback adapter/test hunks and helper updates needed to preserve `singletonCallbackAdapter`; no unrelated worktree hunks imported. Next action: run required focused Go test.
- 2026-05-17 01:44:11 CEST: Tests started. Files touched since last update: none. Decision/blocker: because code/test owner files were touched, run focused Go selector, full Go bridge package, and practical Flutter bridge guard. Next action: `(cd go-mknoon && go test ./bridge -run 'TestBB001|TestNodeCallbackAdapter' -count=1)`.
- 2026-05-17 01:44:11 CEST: Focused Go test completed. Command: `(cd go-mknoon && go test ./bridge -run 'TestBB001|TestNodeCallbackAdapter' -count=1)`. Result: PASS, `ok github.com/mknoon/go-mknoon/bridge 0.571s`. Decision/blocker: no blocker. Next action: `(cd go-mknoon && go test ./bridge -count=1)`.
- 2026-05-17 01:44:11 CEST: Full Go bridge package test completed. Command: `(cd go-mknoon && go test ./bridge -count=1)`. Result: PASS, `ok github.com/mknoon/go-mknoon/bridge 108.810s`. Decision/blocker: no blocker. Next action: `flutter test test/core/bridge/go_bridge_client_test.dart`.
- 2026-05-17 01:44:11 CEST: Flutter bridge guard completed. Command: `flutter test test/core/bridge/go_bridge_client_test.dart`. Result: PASS, `All tests passed!` with 73 test assertions reported by Flutter output. Decision/blocker: no blocker. Next action: QA/self-review diff, status, and whitespace checks.
- 2026-05-17 01:44:11 CEST: QA/self-review started. Files to inspect: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, current plan. Commands planned: `git diff --check`, `git diff --stat -- ...`, `git status --short`. Decision/blocker: no blocker. Next action: run QA/self-review commands.
- 2026-05-17 01:44:11 CEST: QA/self-review completed. Commands: `git diff --check` PASS with no output; `git diff --stat -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go ...` showed only the two tracked bridge files in diff stats because this plan is untracked; `git status --short` confirmed touched session files plus pre-existing unrelated dirty files. Decision/blocker: scoped patch and tests satisfy the BB-001 integration contract; no blocker. Next action: write final execution verdict.
- 2026-05-17 01:44:11 CEST: Final execution verdict recorded. Files touched by this session: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, current INTEGRATE-BB-001 plan. Decision/blocker: final execution verdict `accepted`; no blocker; integration breakdown intentionally not updated because the execution prompt reserves that for the closure agent/controller. Next action: hand off concise execution result.

## Final Verdict

`execution-ready` for standard integration mode.

This is not gap-closure mode. Do not recreate, rewrite, or rerun the historical BB-001 implementation plan. Reuse the worktree plan and closure notes only as evidence for the row-owned delta that may need to be imported into main.

## real scope

Own exactly integration session `INTEGRATE-BB-001`, source row `BB-001`: "Repeated native `Initialize` cannot strand Flutter behind an old callback."

The only candidate code/test delta is the worktree-owned BB-001 Go bridge callback adapter change:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

The plan may update the integration breakdown ledger after verification. It must not update the original worktree source matrix, recreate the original BB-001 plan, broaden into later BB rows, or import unrelated worktree changes from the same files.

## closure bar

The session can close only when one of these is true:

- `accepted`: main has the BB-001 row-owned adapter behavior and tests, row-focused tests plus affected main tests pass, and the integration ledger records concrete evidence.
- `skipped_already_present`: a fresh compare proves main already has the same row-owned behavior and tests, focused tests pass or are documented as already covered by current green evidence, and no code/test delta is applied.
- `blocked_conflict`: current main has conflicting changes in the same owner files or overlapping tests that cannot be resolved within BB-001 without mapping affected rows from both breakdowns.
- `blocked_external_fixture`: only use if required closure evidence depends on unavailable non-repo fixtures. This is not expected for BB-001 because the required proof is host-side Go plus Flutter bridge guard.

## source of truth

- Integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- Historical row plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md`
- Historical source matrix/breakdown/test inventory under `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/`
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- Current main code and tests win over stale prose when there is disagreement.

## session classification

`implementation-ready`

Planning evidence shows current main still has the old immutable `nodeCallbackAdapter` and `Initialize` only creates a callback adapter when `singletonNode == nil`, while the worktree has the accepted BB-001 adapter update and tests. If the executor's fresh pre-edit compare proves those deltas are already present, reclassify the execution result to `skipped_already_present`.

## exact problem statement

This is an integration problem, not a new feature design. The worktree already accepted BB-001 with code and test evidence. Main must either receive the missing row-owned delta or explicitly skip it if the row is already present.

Current main evidence collected during planning:

- `go-mknoon/bridge/bridge.go` defines `nodeCallbackAdapter` with a direct `cb EventCallback` field.
- `Initialize(cb)` currently calls `node.New(&nodeCallbackAdapter{cb: cb})` only when `singletonNode == nil`.
- `go-mknoon/bridge/bridge_test.go` has `TestNodeCallbackAdapter_ForwardsRelayStateEventUntouched` but lacks `TestNodeCallbackAdapter_SetCallbackSwapsAndDropsNil` and `TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents`.

Historical worktree evidence:

- BB-001 final execution verdict is `accepted`.
- Worktree `bridge.go` adds `singletonCallbackAdapter`, thread-safe `nodeCallbackAdapter.SetCallback`, nil-safe `OnEvent`, and repeated `Initialize` callback refresh while preserving the singleton node.
- Worktree `bridge_test.go` adds adapter swap/nil coverage and `TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents`.

## files and repos to inspect next

Before editing, inspect these exact files in both main and worktree:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

Also inspect, read-only:

- BB-001 source plan final execution result and owner-file sections.
- Integration breakdown ledger row for `INTEGRATE-BB-001`.
- COMPLETE_1 breakdown for exact-path overlap and any newly added main rows touching the same files since this plan was written.
- `git status --short` in main.

## existing tests covering this area

Main currently has bridge package tests, including `TestNodeCallbackAdapter_ForwardsRelayStateEventUntouched`, but it does not have row-named BB-001 callback replacement proof.

The worktree BB-001 proof passed historically:

```bash
(cd go-mknoon && go test ./bridge -run 'TestBB001|TestNodeCallbackAdapter' -count=1)
(cd go-mknoon && go test ./bridge -count=1)
flutter test test/core/bridge/go_bridge_client_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
```

Those historical commands are evidence only. The executor must run fresh row-focused validation in main after any integration edit.

## regression/tests to add first

Do not invent new tests. Import only the missing BB-001 row-owned tests from the worktree if they are absent in main:

- `TestNodeCallbackAdapter_SetCallbackSwapsAndDropsNil`
- `TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents`

If main already has equivalent tests with different names, stop and classify the overlap before adding duplicates.

## step-by-step implementation plan

1. Confirm main dirty state. Preserve unrelated edits such as current modified `go-mknoon/bin/testpeer`, `info.plist`, `pubspec.yaml`, and untracked integration docs.
2. Re-read the BB-001 historical plan final execution result and the source matrix/breakdown row evidence. Use it only as historical evidence.
3. Re-check COMPLETE_1 exact-path overlap for `go-mknoon/bridge/bridge.go` and `go-mknoon/bridge/bridge_test.go`. Planning-time exact-path grep found no matches, but execution must verify current state.
4. Compare worktree versus main for the BB-001 owner deltas only:
   - `singletonCallbackAdapter *nodeCallbackAdapter`
   - `nodeCallbackAdapter` `sync.RWMutex` guarded callback storage
   - `SetCallback(cb EventCallback)`
   - nil-safe `OnEvent`
   - `Initialize` updating the stable adapter on every call before preserving or creating `singletonNode`
   - the two BB-001/adapter tests listed above
5. If all meaningful BB-001 behavior and tests are already present in main, do not edit code. Run focused tests if practical and update the integration ledger as `skipped_already_present` with file/test evidence.
6. If the delta is missing and no conflict exists, patch only the missing BB-001 code/test hunks into main. Do not copy unrelated worktree hunks such as broad imports, malformed-input validation, metadata preservation, command-map changes, formatting churn, or rows like BB-015, BB-016, ST-010, or other bridge changes.
7. Run focused tests and any affected main tests listed below.
8. Update the integration breakdown ledger row for `INTEGRATE-BB-001` with exactly one final status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## risks and edge cases

- The worktree bridge files are dirty and include non-BB-001 changes from other rows. Importing whole-file diffs would overreach.
- Main has unrelated dirty files. Do not revert, reformat, stage, or explain them away as this session's work.
- If a current main row has independently changed callback initialization, compare semantics before importing tests or helpers.
- The adapter must update callbacks without replacing `singletonNode` or clearing native group state.
- A nil callback must not panic future event delivery.

## exact tests and gates to run

Required focused tests after code/test integration, or after skip proof if practical:

```bash
(cd go-mknoon && go test ./bridge -run 'TestBB001|TestNodeCallbackAdapter' -count=1)
```

If `go-mknoon/bridge/bridge.go` or `go-mknoon/bridge/bridge_test.go` is touched, also run:

```bash
(cd go-mknoon && go test ./bridge -count=1)
```

Supporting bridge guard if practical:

```bash
flutter test test/core/bridge/go_bridge_client_test.dart
```

Run additional COMPLETE_1/main affected tests only if the fresh overlap check finds a current main row or changed file that intersects the BB-001 hunks.

## known-failure interpretation

The focused Go selector must pass for `accepted` unless a real unrelated environment failure is proven. If full `go test ./bridge -count=1` fails outside BB-001, record the exact failing test names and determine whether the failure predates the BB-001 edit before accepting.

Do not use old worktree green runs as a substitute for fresh main validation. Do not convert unrelated Flutter bridge failures into BB-001 blockers unless they involve callback replacement, event routing, or the files touched by this integration.

## done criteria

- Owner-file delta is either integrated into main or proven already present.
- No unrelated worktree hunks are copied into main.
- Required focused Go test result is recorded.
- Full bridge package test result is recorded if code/test files are touched.
- Flutter bridge guard result is recorded when practical, or explicitly marked unrun with reason.
- Integration breakdown ledger row for `INTEGRATE-BB-001` records exactly one allowed final status and evidence.
- Final closure evidence names changed files, skipped files, test commands, and any blockers.

## scope guard

Do not edit production or test code during planning. During execution, edit only the two owner files unless a fresh conflict requires stopping:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

Do not modify Dart bridge code, platform bridge code, node dispatcher code, group membership, key logic, topic joins, inbox replay, relay transport, notification routing, media handling, broad docs, or test inventory for this session unless the integration ledger update itself requires a narrow doc edit.

## accepted differences / intentionally out of scope

- BB-001 does not require true 3-party proof; historical worktree closure explicitly left it as supporting/recommended only.
- Flutter `GoBridgeClient.reinitialize()` behavior is a supporting guard, not the native BB-001 closure seam.
- COMPLETE_1 rows that touch Go node publish/discovery/relay behavior remain separate and must not be reopened from this session.

## dependency impact

Later `INTEGRATE-BB-*` sessions may assume the native bridge callback adapter is current only after this session is `accepted` or `skipped_already_present`. If this session is `blocked_conflict`, pause dependent bridge lifecycle integration rows until the conflict is mapped against both the full-with-rules integration breakdown and COMPLETE_1.

## reviewer pass

Sufficient with adjustments. Required adjustments were included: exact owner files/tests, standard integration mode, dirty-worktree note, skip/accepted/blocker ledger statuses, focused main validation, and explicit guard against importing unrelated worktree bridge changes.

## arbiter decision

No structural blockers remain. Incremental details intentionally deferred to execution: exact line placement for `singletonCallbackAdapter` and test helper positioning in current main context.

## exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`

## why the plan is safe to implement now

The contract is narrow, file-owned, and testable. It requires a fresh compare before edits, imports only the missing BB-001 adapter/test delta, preserves unrelated dirty state, and has explicit skip and conflict exits if main already contains or conflicts with the worktree behavior.

## Final Execution Result

- final execution verdict: `accepted`
- changed files: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-001-plan.md`
- imported BB-001 delta: stable `singletonCallbackAdapter`, thread-safe `nodeCallbackAdapter.SetCallback`, nil-safe `OnEvent`, repeated `Initialize` callback refresh without replacing `singletonNode`, adapter singleton preservation in bridge tests, `TestNodeCallbackAdapter_SetCallbackSwapsAndDropsNil`, and `TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents`
- files intentionally not changed: integration breakdown ledger and unrelated dirty files (`go-mknoon/bin/testpeer`, `info.plist`, `pubspec.yaml`)
- tests run:
  - `(cd go-mknoon && go test ./bridge -run 'TestBB001|TestNodeCallbackAdapter' -count=1)` PASS, `ok github.com/mknoon/go-mknoon/bridge 0.571s`
  - `(cd go-mknoon && go test ./bridge -count=1)` PASS, `ok github.com/mknoon/go-mknoon/bridge 108.810s`
  - `flutter test test/core/bridge/go_bridge_client_test.dart` PASS, `All tests passed!` with 73 assertions reported
  - `git diff --check` PASS with no output
- blocker: none
