# INTEGRATE-BB-002 Plan: Group Commands Before Native Initialization Fail Explicitly

Status: accepted

Mode: standard integration. This is not gap-closure mode.

## Planning Progress

| timestamp | role | files inspected since last update | decision / blocker | next action |
|---|---|---|---|---|
| 2026-05-17 01:56 CEST | Evidence Collector completed | Integration breakdown, source BB-002 matrix row, historical BB-002 plan, COMPLETE_1 breakdown, main/source owner-file marker searches, current `git status --short` | BB-002 source work is tests-only and accepted in the worktree. Main has no `BB-002` markers in the six Flutter owner files at planning time; main already has Go group `NOT_INITIALIZED` tests. | Draft minimal integration contract. |
| 2026-05-17 01:56 CEST | Planner completed | Same evidence plus COMPLETE_1 owner-file overlap search | Plan is standard worktree-to-main integration: import or skip only missing row-owned test deltas, preserve BB-001 and unrelated dirty state, then update the integration ledger. | Run reviewer/arbiter pass. |
| 2026-05-17 01:56 CEST | Reviewer completed | Draft contract, owner-file table, overlap table, test contract, done criteria, scope guard | Sufficient for execution if the future executor rechecks exact hunks before editing and stops on overlap conflicts. | Mark execution-ready. |
| 2026-05-17 01:56 CEST | Arbiter completed | Reviewer finding and final contract | No structural blockers remain. | Execute later through the integration pipeline. |

## Real Scope

Integrate source row `BB-002` from `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline` into the main checkout only if its row-owned proof is missing.

The row contract is: before native `Initialize`, `group:create`, `group:join`, `group:publish`, `group:updateKey`, and `group:inboxRetrieve` fail explicitly with `NOT_INITIALIZED`, and Flutter callers do not create false local group, member, key, key-promotion, or pending/sending publish state.

This plan does not recreate, rewrite, or rerun the original BB-002 implementation plan. The historical plan is evidence only.

## Source Of Truth

- Active integration ledger: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- Source worktree row plan, historical evidence only: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-002-plan.md`
- Source worktree matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`, row `BB-002`
- Source worktree breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- Current main code/tests win over stale prose when they disagree, but BB-002 source files must be used to identify exact row-owned deltas.

## Dirty Worktree Note

The main checkout is already dirty. Preserve this state and do not revert or overwrite it:

- Prior-session BB-001 state to preserve: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`
- Other dirty paths observed during planning: `go-mknoon/bin/testpeer`, `info.plist`, `pubspec.yaml`
- Existing untracked integration docs observed during planning: the integration breakdown, BB-001 integration plan, and a related full-rules-to-COMPLETE_1 integration breakdown

Before any future edit, run `git status --short` again. If a target BB-002 owner file has unrelated dirty changes, inspect and work around them. Do not revert user or prior-session edits.

## Session Classification

`implementation-ready` for standard integration, tests-only import.

If every BB-002 proof is already present in main at execution time, classify the integration result as `skipped_already_present`. If importing the missing row-owned delta conflicts with COMPLETE_1-owned behavior or unrelated dirty edits, stop as `blocked_conflict`. No external fixture is expected for BB-002.

## Worktree-Owned Files And Tests

Historical BB-002 execution changed only these six Flutter test files:

| owner file | BB-002 worktree-owned proof to import or skip |
|---|---|
| `test/core/bridge/bridge_group_helpers_test.dart` | `group('BB-002 NOT_INITIALIZED', ...)` covering `callGroupCreate`, plain/config `callGroupJoin`, `callGroupPublish`, `callGroupUpdateKey`, and `callGroupInboxRetrieve` error-code preservation. |
| `test/features/groups/application/create_group_use_case_test.dart` | `BB-002 group:create NOT_INITIALIZED does not persist group member or key`. |
| `test/features/groups/application/join_group_use_case_test.dart` | `BB-002 group:join NOT_INITIALIZED does not persist group member or key`. |
| `test/features/groups/application/send_group_message_use_case_test.dart` | `BB-002 group:publish NOT_INITIALIZED does not leave a pending send`. |
| `test/features/groups/application/group_key_update_listener_test.dart` | `BB-002 group:updateKey NOT_INITIALIZED keeps current key unchanged`. |
| `test/features/groups/application/rejoin_group_topics_use_case_test.dart` | `BB-002 group:join NOT_INITIALIZED records error without local mutation`. |

Verification-only surfaces from the historical plan:

- `test/core/bridge/go_bridge_client_test.dart` was included in the required direct Flutter run for command-map coverage, but the BB-002 execution did not list it as a changed file.
- `go-mknoon/bridge/bridge_test.go` already had command-level Go proof for `TestGroup(Create|JoinTopic|Publish|UpdateKey|InboxRetrieve)_NodeNotInitialized`; it is verification-only for this integration and must preserve BB-001 edits.

## Current Main Comparison Snapshot

Planning-time checks found:

- `rg -l "BB-002" test/core/bridge test/features/groups/application go-mknoon/bridge` in main returned no Flutter owner files.
- The same `BB-002` marker search in the source worktree returned the six owner files listed above.
- Main `go-mknoon/bridge/bridge_test.go` already contains the group `NOT_INITIALIZED` tests used by the BB-002 Go verification command.
- SHA comparison showed all six owner files differ between main and the source worktree, so the executor must not copy whole files. Import only BB-002-named test blocks and any smallest required local imports/helpers.

These are planning-time facts, not permission to edit blindly. Re-run the marker search and inspect exact hunks immediately before applying any delta.

## COMPLETE_1 Compatibility And Overlap

The integration breakdown's known overlap guard has no explicit BB-002 mapping. The main COMPLETE_1 breakdown does identify shared file surfaces that must be protected:

| BB-002 surface | COMPLETE_1 overlap discovered | integration instruction |
|---|---|---|
| `test/features/groups/application/send_group_message_use_case_test.dart` | Rows including `GO-001`, `GO-002`, `GO-008`, `GP-007`, `GM-032`, and `GE-012` use or changed this file. | Insert only the BB-002 `NOT_INITIALIZED` publish test. Do not alter zero-peer, inbox-failure, privacy/redaction, group-dissolve, or same-user-device tests. Run the full file after edits. |
| `test/features/groups/application/rejoin_group_topics_use_case_test.dart` | `GL-018` uses this file for startup/rejoin proof. | Insert only the BB-002 rejoin error-counter/no-mutation test. Do not alter restart/rejoin exactly-once behavior. Run the full file after edits. |
| `test/core/bridge/go_bridge_client_test.dart` | `GO-003`, `GO-004`, and `GO-008` use this file. | Verification-only for BB-002 unless exact command-map coverage is missing. Do not change diagnostic, feedback, or redaction behavior. |
| `test/core/bridge/bridge_group_helpers_test.dart`, `create_group_use_case_test.dart`, `join_group_use_case_test.dart`, `group_key_update_listener_test.dart`, `go-mknoon/bridge/bridge_test.go` | No exact COMPLETE_1 owner-file reference was found in the compatibility breakdown during planning. | Still inspect current files before editing; absence from the breakdown is not proof of no local dirty overlap. |

If a BB-002 hunk would require changing helper setup shared with one of the COMPLETE_1 rows above, stop and mark `blocked_conflict` with the exact files and rows. Do not resolve cross-row behavior inside INTEGRATE-BB-002.

## Step-By-Step Integration Contract

1. Re-run `git status --short` and record dirty paths. Preserve BB-001 changes in `go-mknoon/bridge/bridge.go` and `go-mknoon/bridge/bridge_test.go`.
2. Re-read the BB-002 source row, source plan final verdict, and source owner-file snippets. Do not rewrite the historical plan.
3. Re-run duplicate checks:
   - `rg -n "BB-002|NOT_INITIALIZED" test/core/bridge test/features/groups/application go-mknoon/bridge`
   - `rg -n "BB-002" /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/core/bridge /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application`
4. For each owner file, compare only the BB-002-named worktree test block against main. If the same proof already exists under another name, record the exact selector and skip that file.
5. If missing, apply the smallest BB-002 row-owned test delta. Do not copy whole files from the source worktree. Add only local imports/helpers required by the BB-002 test block.
6. Do not edit production files. Do not edit `go-mknoon/bridge/bridge.go`. Do not edit `go-mknoon/bridge/bridge_test.go` unless the Go verification tests are absent and the hunk is strictly the already-accepted `NodeNotInitialized` test proof; planning-time evidence says they are present.
7. Run required direct tests. If a direct BB-002 assertion fails because production behavior is missing, stop and mark `blocked_conflict` or request a new code-and-tests plan; do not silently broaden this integration contract.
8. Update only the integration breakdown ledger for `INTEGRATE-BB-002` after execution, with exactly one final status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Exact Tests And Gates To Run

Required direct Flutter proof:

```bash
flutter test \
  test/core/bridge/go_bridge_client_test.dart \
  test/core/bridge/bridge_group_helpers_test.dart \
  test/features/groups/application/create_group_use_case_test.dart \
  test/features/groups/application/join_group_use_case_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/group_key_update_listener_test.dart \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart
```

Required Go verification proof:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroup(Create|JoinTopic|Publish|UpdateKey|InboxRetrieve)_NodeNotInitialized'
```

Affected COMPLETE_1/main tests are covered by the full owner-file Flutter command above for `send_group_message_use_case_test.dart`, `rejoin_group_topics_use_case_test.dart`, and `go_bridge_client_test.dart`.

`./scripts/run_test_gates.sh groups` is not required if this remains tests-only and production stays untouched. If any production file is touched despite the guard, stop before broadening and write a new plan or mark the session blocked.

## Known-Failure Interpretation

A new failure in a BB-002-named test or the Go `NodeNotInitialized` selector is blocking for this integration session.

If a broad owner-file run exposes a pre-existing unrelated failure in another row, isolate BB-002 with targeted selectors, record the unrelated failure separately, and do not mark BB-002 accepted until its direct proof is green or truthfully blocked.

Do not use generic bridge error tests as BB-002 closure evidence unless they assert `NOT_INITIALIZED` for the five source commands and the no-false-local-state contract.

## Done Criteria

INTEGRATE-BB-002 is done when one of these outcomes is recorded:

- `accepted`: missing BB-002 row-owned deltas are integrated, no production files changed, direct Flutter and Go proof pass, affected COMPLETE_1 owner-file tests remain compatible, and the integration ledger is updated with exact file/test evidence.
- `skipped_already_present`: main already has equivalent BB-002 proof for all six Flutter owner surfaces plus Go verification proof, with exact selectors and command evidence recorded.
- `blocked_conflict`: an exact conflict with dirty main state or COMPLETE_1-owned behavior prevents a safe BB-002-only import, with conflicting files/rows named.
- `blocked_external_fixture`: only if an unexpected non-repo fixture prevents required evidence. This is not expected for BB-002.

## Scope Guard

Do not:

- recreate, rewrite, or rerun the original BB-002 implementation plan as a new implementation plan;
- mutate source worktree artifacts;
- edit production code, bridge initialization lifecycle, command names, retry semantics, DB schema, networking, UI, device harnesses, relay scripts, or named gate definitions;
- broaden into BB-001, BB-003, BB-014, BB-015, BB-011/BB-012, COMPLETE_1 GO/GL/GM/GE rows, membership lifecycle, key epoch, inbox replay, media, network, UI, security, or observability rows;
- copy whole source worktree files into main;
- revert BB-001 or unrelated dirty user changes.

Overengineering for this session means adding harnesses, fake-network layers, simulator/device proof, broad named gates, or production abstractions when the accepted source row was direct tests-only.

## Accepted Differences / Intentionally Out Of Scope

- Main already has Go command-level `NOT_INITIALIZED` coverage; BB-002 integration is expected to be Flutter test import plus Go verification, not native behavior work.
- A publish failure may leave a failed retryable row, but BB-002 requires no pending/sending false-success state after `NOT_INITIALIZED`.
- Cursor-based inbox drain remains supplemental; BB-002 source row names `group:inboxRetrieve`, so direct helper coverage for that command is sufficient.
- Device, relay, fake-network, simulator, and 3-party proof are out of scope.

## Dependency Impact

This integration only supplies bootstrap/bridge-contract proof that later rows may cite for pre-initialization failure handling. It does not close or alter adjacent startup/rejoin recovery, membership, key epoch, inbox replay, send reliability, diagnostics/privacy, UI, or network rows.

If BB-002 cannot be safely imported, later integration sessions can continue only if they do not depend on the missing BB-002 proof; the ledger must clearly record the blocker.

## Final Closure Evidence Requirements

When execution finishes, the closure note in the integration breakdown must include:

- final status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`;
- exact main files changed, or explicit no-change skip evidence;
- exact BB-002 test selectors present in main;
- exact commands run and pass/fail summaries;
- current dirty-worktree preservation statement, including BB-001 bridge files;
- if blocked, exact conflicting files, COMPLETE_1 rows, or external fixture signature;
- explicit statement that production files were not changed, or a blocker if that guard could not be honored.

## Execution Progress

| timestamp | role | files inspected since last update | decision / blocker | next action |
|---|---|---|---|---|
| 2026-05-17 01:59 CEST | Execution agent started | `git status --short`, execution contract plan, pipeline-orchestrator skill instructions | Pre-edit dirty state recorded: `M go-mknoon/bin/testpeer`; `M go-mknoon/bridge/bridge.go`; `M go-mknoon/bridge/bridge_test.go`; `M info.plist`; `M pubspec.yaml`; untracked integration docs including this plan and BB-001/session breakdown artifacts. BB-001 bridge edits and unrelated dirty paths must be preserved. | Extract source BB-002 contract and compare main/worktree owner deltas before deciding patch or skip. |
| 2026-05-17 01:59 CEST | Contract extracted | Source matrix row, source BB-002 plan markers/final verdict, main/source `rg` marker scans | Historical BB-002 is `accepted` and `Covered`; source has BB-002 markers in the six Flutter owner files. Main has Go `NOT_INITIALIZED` bridge proof but no Flutter `BB-002` markers in the six owner files, so exact block comparison is required before patching. | Inspect source BB-002 blocks and corresponding main owner-file contexts for duplicates or conflicts. |
| 2026-05-17 02:04 CEST | Local execution fallback started | BB-002 execution child progress, current plan, six source worktree BB-002 test blocks, six main owner files, `git status --short` | Fresh child recorded comparison intake but did not produce patch/test progress after a bounded progress request. Controller closed the child and used the single allowed local execution fallback for INTEGRATE-BB-002. Main still lacked BB-002 Flutter markers; Go `NodeNotInitialized` tests already exist. | Patch only BB-002 row-named Flutter tests and the smallest local test-helper adjustment. |
| 2026-05-17 02:04 CEST | Local fallback patch completed | `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/join_group_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart` | Imported only the six BB-002 row-named Flutter proof blocks plus one local `BridgeCommandException` matcher/import and one `_UpdateKeyFailBridge(errorCode:)` test-helper parameter. No production files changed; BB-001 bridge files were preserved. | Run Dart format check, required Flutter proof, required Go verification, and diff hygiene. |
| 2026-05-17 02:09 CEST | BB-002 selector fix completed | `test/core/bridge/bridge_group_helpers_test.dart`, source BB-002 block, main helper behavior | Focused BB-002 selector found one mismatch: source worktree expected legacy `callGroupJoin` to stop as `LEGACY_JOIN_UNSUPPORTED`, which belongs to the later BB-006 legacy-helper row. Main currently returns `NOT_INITIALIZED`, which satisfies BB-002 without importing BB-006 behavior. Adjusted only the BB-002 helper test expectation to `NOT_INITIALIZED` and removed the source-specific no-send assertion. | Re-run BB-002 selectors, then full required Flutter proof. |
| 2026-05-17 02:10 CEST | Tests and QA completed | Six BB-002 Flutter owner files, Go bridge verification selector, current dirty worktree, diff hygiene | PASS: `dart format --set-exit-if-changed` on six edited Dart test files; PASS: BB-002-only selector run (`+10`); PASS: full required Flutter command (`+295`); PASS: `cd go-mknoon && go test ./bridge -run 'TestGroup(Create|JoinTopic|Publish|UpdateKey|InboxRetrieve)_NodeNotInitialized'` (`ok ... 0.540s`); PASS: `git diff --check`. No production files changed and BB-001 bridge files remained prior-session state. | Record final execution result for closure. |

## Final Execution Result

- final execution verdict: `accepted`
- changed files:
  - `test/core/bridge/bridge_group_helpers_test.dart`
  - `test/features/groups/application/create_group_use_case_test.dart`
  - `test/features/groups/application/join_group_use_case_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-002-plan.md`
- production files touched: none
- BB-001 prior-session files preserved: `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`
- imported BB-002 delta: row-named Flutter tests proving `NOT_INITIALIZED` for `group:create`, `group:join`, `group:publish`, `group:updateKey`, `group:inboxRetrieve`, and no false local group/member/key/key-promotion or pending/sending publish state.
- intentional source deviation: the source worktree helper test expected legacy `callGroupJoin` to stop as `LEGACY_JOIN_UNSUPPORTED`; main was kept BB-002-scoped by asserting the current explicit `NOT_INITIALIZED` failure and leaving BB-006 legacy-helper behavior to `INTEGRATE-BB-006`.
- tests run:
  - `dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart` PASS, `Formatted 6 files (0 changed)`
  - `flutter test test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name BB-002` PASS, `All tests passed!` with `+10`
  - `flutter test test/core/bridge/go_bridge_client_test.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/join_group_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart` PASS, `All tests passed!` with `+295`
  - `cd go-mknoon && go test ./bridge -run 'TestGroup(Create|JoinTopic|Publish|UpdateKey|InboxRetrieve)_NodeNotInitialized'` PASS, `ok github.com/mknoon/go-mknoon/bridge 0.540s`
  - `git diff --check -- <BB-002 edited test files and plan>` PASS with no output
- blocker: none
| 2026-05-17 02:01 CEST | Fresh owner-file comparison completed | Source/main snippets for the six BB-002 owner test files; current `lib/core/bridge/bridge_group_helpers.dart` and `lib/features/groups/application/join_group_use_case.dart` API shape for compatibility only | BB-002 proof is missing from main Flutter owner files. No exact equivalent under another name was found for explicit `NOT_INITIALIZED` plus no-false-local-state coverage. Source test blocks require small reconciliation to current main helper/use-case APIs; no production edit is allowed or needed. | Patch only BB-002 row-named tests plus the smallest local test imports/helper support, then run required Flutter and Go commands. |
