Status: accepted

# INTEGRATE-BB-008 Standard Integration Plan

## Planning Progress

- 2026-05-17T03:45:00+02:00 - Evidence Collector completed. Files inspected since last update: source BB-008 matrix row, source BB-008 session breakdown entry, source BB-008 plan, source test-inventory closure note, source commit `85da7914aa5c8eedabfdbffda11d16a66382a8ea`, main integration breakdown, main COMPLETE_1 compatibility artifact, main BB-008 duplicate searches. Decision/blocker: BB-008 source delta is concrete and not already present in main. Next action: draft standard integration contract.
- 2026-05-17T03:50:00+02:00 - Planner completed. Files inspected since last update: source commit changed-file list and main affected-file symbol searches. Decision/blocker: plan should import only five meaningful code/test files and use source closure docs as evidence only. Next action: reviewer sufficiency pass.
- 2026-05-17T03:53:00+02:00 - Reviewer completed. Files inspected since last update: draft plan scope, COMPLETE_1 overlap rows GL-002/GL-018/GR-006/GR-016, source RA-015 overlap language, main dirty status evidence. Decision/blocker: sufficient with explicit conflict stop/map rule and accepted/skipped/blocked terminal statuses. Next action: arbiter pass.
- 2026-05-17T03:55:00+02:00 - Arbiter completed. Files inspected since last update: final plan sections and source/main evidence. Decision/blocker: no structural blocker; standard integration, not gap-closure. Next action: execute later in a separate implementation pass.

## Execution Progress

- 2026-05-17T04:09:00+02:00 - Executor inspected source BB-008 row evidence, source commit `85da7914aa5c8eedabfdbffda11d16a66382a8ea`, main duplicate state, and COMPLETE_1 overlaps. Decision/blocker: BB-008 helper, bridge refresh path, and row-owned selectors were missing from main; no conflict found. Next action: import only the five meaningful BB-008 code/test files.
- 2026-05-17T04:27:00+02:00 - Executor imported the missing BB-008 row-owned delta into `go-mknoon/bridge/bridge.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/node/pubsub_test.go`, and `test/features/groups/application/rejoin_group_topics_use_case_test.dart`. Decision/blocker: source docs were not copied; COMPLETE_1 docs were untouched; BB-009+, RA-015, and external harness work remained out of scope. Next action: run focused and affected tests.
- 2026-05-17T04:46:00+02:00 - Verification completed. Decision/blocker: focused BB-008 proof, affected BB-006/BB-007/GL-018/GR-006/GR-016 selectors, `groups`, `baseline`, and `git diff --check` passed. Next action: mark `INTEGRATE-BB-008` accepted and continue with `INTEGRATE-BB-009`.

## real scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-008` / source row `BB-008`: already-joined recovery with newer key/config cannot report success while staying stale.

The executor must import, reconcile, or skip only the meaningful BB-008 delta already implemented in the source worktree. Do not recreate the source implementation plan, do not rerun the original rollout plan, and do not broaden into new gap closure.

In scope:

- Inspect the source BB-008 row, source BB-008 plan/evidence/closure, source commit, and main duplicate state before editing.
- Import only missing BB-008-owned code/test delta into main:
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/node/pubsub.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/node/pubsub_test.go`
  - `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- Preserve already accepted main integration rows BB-001 through BB-007.
- Preserve overlapping COMPLETE_1 behavior for GL-002, GL-018, GR-006, and GR-016.
- Update only this integration plan and the integration breakdown ledger after execution.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or the historical source BB-008 plan into main.
- Do not edit main COMPLETE_1 docs for this row.
- Do not import BB-009+, RA-015, leave/recovery ordering, device/relay/3-party harness, UI, notification, media, observability, or broad security work.
- Do not change unrelated dirty files or reformat broad files.

## closure bar

The row is good enough when main contains the BB-008 source behavior or proves it was already present:

1. `GroupJoinTopic` handles `already joined group topic:` by refreshing newer config/key material before returning `ALREADY_JOINED` success, or returns an explicit error if refresh is impossible.
2. Native node state updates config and key together only for strictly newer key epochs.
3. Same-epoch and older duplicate joins remain idempotent and do not overwrite current key/config state.
4. Flutter rejoin recovery sends latest full config/key material when Go reports `ALREADY_JOINED`.
5. BB-006, BB-007, GL-002, and relevant main/COMPLETE_1 recovery/rejoin selectors still pass.
6. The integration ledger records one terminal status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## source of truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-008`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-008`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md`.
- Source closure evidence: source `test-inventory.md` BB-008 row and source matrix BB-008 covered note.
- Source commit evidence: `85da7914aa5c8eedabfdbffda11d16a66382a8ea` (`BB-008: refresh already joined group state`, committed 2026-05-10 23:49:01 +0200).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## session classification

`implementation-ready`

Reason: the source BB-008 code/test delta and commit are discoverable, main lacks the row-owned helper and test selectors, and the integration can be bounded to five meaningful code/test files plus ledger evidence. This is not a gap-closure session.

## exact problem statement

The source worktree closed BB-008 by preventing a native stale-success path: a duplicate `group:join` for an already joined group can carry newer epoch config/key material, and success must not be returned while Go remains on stale state.

Main currently still has `go-mknoon/bridge/bridge.go` returning `{ok: true, note: "ALREADY_JOINED"}` directly in the duplicate-join branch, and `go-mknoon/node/pubsub.go` lacks `RefreshJoinedGroupStateIfNewer`. Main also lacks the BB-008 bridge/node/Flutter test selectors. The integration task is to bring over the already proven source delta without duplicating prior BB-007 work or adjacent RA/COMPLETE_1 rows.

## source commit and file evidence

Source commit:

```text
85da7914aa5c8eedabfdbffda11d16a66382a8ea BB-008: refresh already joined group state
```

Changed files in that commit:

```text
A Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
M go-mknoon/bridge/bridge.go
M go-mknoon/bridge/bridge_test.go
M go-mknoon/node/pubsub.go
M go-mknoon/node/pubsub_test.go
M test/features/groups/application/rejoin_group_topics_use_case_test.dart
```

Meaningful integration files are the five code/test files. The four source docs are historical evidence only and must not be copied into main.

Source code evidence:

- `go-mknoon/node/pubsub.go` adds `RefreshJoinedGroupStateIfNewer`, a one-lock helper that requires joined state, rejects missing config/key info, clones config, updates key only when incoming epoch is newer, and preserves previous-key grace metadata.
- `go-mknoon/bridge/bridge.go` calls `n.RefreshJoinedGroupStateIfNewer(params.GroupId, &params.GroupConfig, keyInfo)` before returning `ALREADY_JOINED`.
- `go-mknoon/bridge/bridge_test.go` adds:
  - `TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig`
  - `TestGroupJoinTopic_BB008AlreadyJoinedSameOrOlderEpochDoesNotReplaceCurrentKey`
- `go-mknoon/node/pubsub_test.go` adds:
  - `TestRefreshJoinedGroupStateIfNewerUpdatesConfigAndKeyAtomically`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart` adds:
  - `BB-008 sends latest full config and key material when already joined`

## duplicate presence in main

Observed main state during planning:

- `go-mknoon/bridge/bridge.go` still returns `ALREADY_JOINED` immediately in the duplicate branch and lacks the refresh call.
- `go-mknoon/node/pubsub.go` has `UpdateGroupConfig` and `UpdateGroupKey`, but no `RefreshJoinedGroupStateIfNewer`.
- Searches in main for `RefreshJoinedGroupStateIfNewer`, `TestGroupJoinTopic_BB008`, `TestRefreshJoinedGroupStateIfNewer`, and `BB-008 sends latest full config and key material when already joined` found no matching implementation/tests.
- Main already contains BB-007 tests in `go_bridge_client_test.dart`, `invite_round_trip_test.dart`, `go-mknoon/bridge/bridge_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`; do not duplicate or rewrite them.

If execution-time searches show BB-008 has landed since this plan was written, skip code/test edits and classify the row `skipped_already_present` with exact file/selector evidence.

## files and repos to inspect next

Before editing, inspect:

```bash
git status --short
git diff -- go-mknoon/bridge/bridge.go go-mknoon/node/pubsub.go go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_test.go test/features/groups/application/rejoin_group_topics_use_case_test.dart
git -C /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline show --name-status 85da7914
rg -n "BB-008|BB008|RefreshJoinedGroupStateIfNewer|ALREADY_JOINED" go-mknoon test lib Test-Flight-Improv/Group-Chat-Feature
```

Source files to compare:

```text
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/bridge/bridge.go
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/node/pubsub.go
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/bridge/bridge_test.go
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/go-mknoon/node/pubsub_test.go
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/rejoin_group_topics_use_case_test.dart
```

Main files to update only if missing the BB-008 delta:

```text
go-mknoon/bridge/bridge.go
go-mknoon/node/pubsub.go
go-mknoon/bridge/bridge_test.go
go-mknoon/node/pubsub_test.go
test/features/groups/application/rejoin_group_topics_use_case_test.dart
```

Docs to update after execution:

```text
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-008-plan.md
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## existing tests covering this area

Source BB-008 closure relied on:

- `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB008|TestGroupJoinTopic_AlreadyJoinedIsIdempotent|TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish' -count=1`
- `cd go-mknoon && go test ./node -run 'TestRefreshJoinedGroupStateIfNewer|TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial|TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline' -count=1`
- `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-008'`
- BB-006 and BB-007 preservation selectors
- host macOS `groups`, host macOS `baseline`, and `git diff --check`

Main currently covers adjacent behavior:

- BB-006 and BB-007 from prior integration rows.
- COMPLETE_1 GL-002 duplicate join preserves existing low-level state.
- COMPLETE_1 GL-018 persisted app rejoin sends current config/key after restart.
- COMPLETE_1 GR-006 recovery acknowledgement waits for full app topic rejoin.
- COMPLETE_1 GR-016 watchdog restart rejoins private groups and resumes delivery.

## regression/tests to add first

This is an import contract, so "add first" means import the source row-owned selectors before or with the source production delta, not invent new tests.

Required missing selectors to import if absent:

- `go-mknoon/bridge/bridge_test.go::TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig`
- `go-mknoon/bridge/bridge_test.go::TestGroupJoinTopic_BB008AlreadyJoinedSameOrOlderEpochDoesNotReplaceCurrentKey`
- `go-mknoon/node/pubsub_test.go::TestRefreshJoinedGroupStateIfNewerUpdatesConfigAndKeyAtomically`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart` plain-name `BB-008 sends latest full config and key material when already joined`

Do not add new row behavior beyond source BB-008 unless the source import cannot compile because of main-only API drift. If API drift exists, adapt only the minimum fixture names/types required to preserve the same assertions.

## step-by-step implementation plan

1. Reconfirm `INTEGRATE-BB-007` remains accepted in the integration breakdown and that BB-008 is still `pending_integration`.
2. Re-run duplicate searches in main for `RefreshJoinedGroupStateIfNewer`, `TestGroupJoinTopic_BB008`, `TestRefreshJoinedGroupStateIfNewer`, and the Flutter `BB-008` plain-name.
3. Inspect uncommitted main diffs in the five candidate files. If any uncommitted change overlaps the exact source BB-008 hunks, stop and classify `blocked_conflict` unless the overlap is plainly the same BB-008 delta.
4. Compare the source commit `85da7914` hunks against current main:
   - Bring over the `RefreshJoinedGroupStateIfNewer` helper only if absent.
   - Bring over the bridge duplicate-join refresh call only if absent.
   - Bring over the three row-owned test selectors only if absent.
5. Preserve main-local changes and line drift. Use source commit behavior as the semantic source, not as a blind patch.
6. Do not import source doc changes. Update only this plan's execution notes and the integration breakdown ledger after running tests.
7. Run focused BB-008 tests and affected adjacent tests listed below.
8. Assign one terminal status:
   - `accepted`: missing meaningful BB-008 delta imported and required tests/gates pass or unrelated known failures are documented.
   - `skipped_already_present`: all meaningful BB-008 delta was already present in main with concrete helper/test evidence.
   - `blocked_conflict`: main has overlapping unmerged changes or COMPLETE_1 behavior that cannot be reconciled within row scope.
   - `blocked_external_fixture`: only if execution discovers BB-008 acceptance requires unavailable external device/relay fixture. This is not expected for BB-008 because source closure was host-side.

## conflict stop/map rule

Stop before editing and map conflicts if any of these are true:

- `go-mknoon/node/pubsub.go` already has a differently named refresh/update helper for already-joined newer state.
- `go-mknoon/bridge/bridge.go` already handles `ALREADY_JOINED` by a different update/error path.
- The BB-008 source tests fail to compile because main has intentionally changed group config/key APIs beyond fixture adaptation.
- COMPLETE_1 GL-002 duplicate-join preservation would be weakened by the import.
- COMPLETE_1 GL-018, GR-006, or GR-016 recovery/rejoin behavior would need product changes outside the five row-owned files.
- RA-015 remove/re-add convergence appears necessary to make BB-008 pass.

When stopped, record:

- exact conflicting files/hunks
- source row(s): `BB-008` and any adjacent source rows implicated, especially `RA-015`
- main/COMPLETE_1 rows implicated: at minimum GL-002, GL-018, GR-006, GR-016 if touched
- recommended next action

Do not resolve such conflicts inside this row without a new controller decision.

## risks and edge cases

- The main worktree is dirty; affected files may include user or previous-session edits. Preserve them unless they are exactly the missing BB-008 delta.
- `RefreshJoinedGroupStateIfNewer` must keep `node.JoinGroupTopic` duplicate-join rejection semantics intact for GL-002.
- Same-epoch or older duplicate joins must not overwrite key/config state.
- The bridge response may keep `note: "ALREADY_JOINED"`; compatibility matters more than adding response fields.
- Flutter-side BB-008 proof is only payload evidence. Do not claim RA-015 full Flutter/Go re-add convergence.
- Host-side BB-008 closure does not satisfy recommended fake-network or 3-party E2E proof.

## exact tests and gates to run

Focused BB-008 proof:

```bash
cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB008|TestGroupJoinTopic_AlreadyJoinedIsIdempotent|TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish' -count=1
cd go-mknoon && go test ./node -run 'TestRefreshJoinedGroupStateIfNewer|TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial|TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline' -count=1
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-008'
```

Affected main/COMPLETE_1 preservation:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupJoinWithConfig'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'BB-007'
flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-006'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
```

Smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
git diff --check
```

If `baseline` is too broad for the integration executor's time budget, it may be skipped only with a plan execution note explaining why and with all focused/affected selectors passing. The source row did run baseline, so default is to run it.

## known-failure interpretation

- Failures in `TestGroupJoinTopic_BB008*`, `TestRefreshJoinedGroupStateIfNewer*`, or Flutter plain-name `BB-008` are in scope.
- Failures in BB-006, BB-007, GL-002 duplicate join, GL-018 rejoin, GR-006 recovery ack, or GR-016 watchdog rejoin selectors are integration blockers unless proven pre-existing from unchanged main.
- `groups` or `baseline` failures may be classified as unrelated only with exact failing test names and a clear reason they do not touch BB-008 join/config/key/rejoin behavior.
- Missing external simulator/device/relay fixtures should not block BB-008 unless execution unexpectedly broadens into external proof; record `blocked_external_fixture` only for an actual required fixture blocker.

## done criteria

- Source BB-008 row, source plan/closure, source commit, exact changed files, duplicate presence, and COMPLETE_1 overlaps were inspected.
- Main contains the row-owned BB-008 helper/bridge behavior and test selectors, or the row is explicitly `skipped_already_present`.
- No duplicate BB-007, RA-015, or COMPLETE_1 row work was imported.
- Required focused tests and affected preservation selectors pass, or unrelated failures are documented.
- `git diff --check` passes.
- Integration breakdown ledger is updated with one terminal status and concrete evidence.
- This plan records execution outcome, changed files, tests run, skipped duplicate/unrelated work, conflicts, and next session.

## scope guard

Do not:

- Rewrite `node.JoinGroupTopic`.
- Add general config versioning/state-hash semantics.
- Add new recovery orchestration, retry behavior, or UI behavior.
- Implement RA-015.
- Import source docs beyond evidence references.
- Touch COMPLETE_1 docs.
- Use this row to fix unrelated dirty worktree changes.

Overengineering signs:

- New helper APIs beyond the source `RefreshJoinedGroupStateIfNewer` semantics.
- New test harnesses or external fixtures.
- Broad groups gate fixes unrelated to BB-008.
- Reformatting large files outside touched hunks.

## accepted differences / intentionally out of scope

- Source BB-008 used strictly newer `keyEpoch` as the freshness discriminator; same-epoch config-only convergence remains out of scope.
- Fake-network and 3-party E2E were recommended but unclaimed in source closure and remain out of scope for this standard integration.
- RA-015 overlaps `ALREADY_JOINED` language but owns full Go/Flutter config convergence after re-add; this row imports only BB-008's native stale-success fix and Flutter latest-material payload proof.
- COMPLETE_1 GL-002 remains authoritative for low-level duplicate-join preservation; BB-008 adds bridge-level refresh without weakening GL-002.

## dependency impact

BB-009+ and recovery ordering rows may rely on BB-008 only for the invariant that `ALREADY_JOINED` success does not leave native Go stale when newer key/config material is supplied. They must not assume leave/unsubscribe, inbox drain, recovery ack, RA-015, device/relay, or 3-party behavior was integrated here.

If BB-008 blocks, keep `INTEGRATE-BB-009+` pending until the conflict is mapped and resolved or explicitly accepted by the integration controller.

## Reviewer Pass

Verdict: sufficient for a standard integration execution pass.

Findings:

- The plan names the source row, source closure, source commit, exact changed files, duplicate state in main, and COMPLETE_1 overlap rows.
- The plan prevents source doc copying and gap-closure expansion.
- The plan has an explicit conflict stop/map rule and terminal status contract.
- The plan requires focused BB-008 tests plus affected BB-006/BB-007/GL-002/GL-018/GR-006/GR-016 preservation.

## Arbiter Decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact hunk placement in main files because line numbers have drifted.
- Whether `baseline` is run or explicitly skipped by the later executor due time budget.

Accepted differences intentionally left unchanged:

- No fake-network or 3-party proof.
- No RA-015 convergence import.
- No COMPLETE_1 doc edits.

## Final Execution Result

Final verdict: `accepted`.

Accepted files:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-008-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Tests and gates passed:

- `gofmt -w go-mknoon/bridge/bridge.go go-mknoon/node/pubsub.go go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_test.go`
- `dart format test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_BB008|TestGroupJoinTopic_AlreadyJoinedIsIdempotent|TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish' -count=1`
- `cd go-mknoon && go test ./node -run 'TestRefreshJoinedGroupStateIfNewer|TestJoinGroupTopic_DuplicateJoinPreservesExistingState|TestJoinGroupTopic_DuplicateJoinPreservesDelivery|TestUpdateGroupKey_IgnoresSameEpochDifferentMaterial|TestUpdateGroupKey_IgnoresOlderEpochAfterCurrent|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline' -count=1`
- `flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'BB-008'`
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupJoinWithConfig'`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'BB-007'`
- `flutter test --no-pub test/features/groups/application/join_group_use_case_test.dart --plain-name 'BB-006'`
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'`
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- `git diff --check`

Skipped duplicate or unrelated work:

- Source BB-008 docs were reused as evidence only and were not copied into main.
- COMPLETE_1 docs were not edited.
- Existing BB-001 through BB-007 integration work was preserved.
- BB-009+, RA-015, leave/recovery ordering, device/relay/3-party harness, UI, notification, media, observability, and broad security work were not imported.

Blockers: none.

Next session: `INTEGRATE-BB-009`.
