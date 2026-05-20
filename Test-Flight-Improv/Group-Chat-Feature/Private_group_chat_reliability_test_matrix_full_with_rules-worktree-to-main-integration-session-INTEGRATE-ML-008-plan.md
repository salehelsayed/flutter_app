Status: accepted
Acceptance Status: accepted

# INTEGRATE-ML-008 Worktree-to-Main Integration Plan

## Planning Progress

- 2026-05-17T21:41:04+02:00 - Evidence Collector completed. Files inspected since last update: source ML-008 matrix row, source breakdown Session ML-008 block, source ML-008 plan/evidence, main integration breakdown ML-008 mapping, COMPLETE_1 overlap rows GM-022/GM-009/GM-010/GM-024, and current main marker scans. Decision/blocker: source ML-008 includes row proof plus narrow replay/cursor/retry production fixes; main marker scan found no `ML-008`, `private_readd_cycles`, or `ml008CycleProof` anchors, but execution must still classify exact files as present, partial, or missing before import. Next action: write minimal integration contract.
- 2026-05-17T21:41:04+02:00 - Planner completed. Files inspected since last update: source touched-file list, source proof commands, source live proof, and COMPLETE_1 overlap evidence/selectors. Decision/blocker: allow only missing ML-008-owned cycle proof, `private_readd_cycles` support, drain/cursor tests, bridge/Go retry tests, and minimal source-proven cursor/retry production deltas. Next action: reviewer pass.
- 2026-05-17T21:41:04+02:00 - Reviewer completed. Files inspected since last update: complete draft contract, scope guard, focused test list, overlap selector list, and known-failure rule. Decision/blocker: sufficient for execution if the executor performs exact pre-application inspection and does not duplicate COMPLETE_1 coverage. Next action: arbiter pass.
- 2026-05-17T21:41:04+02:00 - Arbiter completed. Files inspected since last update: reviewer findings and closure bar. Decision/blocker: no structural blockers remain; this plan is execution-ready for INTEGRATE-ML-008 only, not accepted. Next action: execute later without moving to ML-009.

## real scope

Process exactly `INTEGRATE-ML-008` for source row `ML-008 | Repeated add-remove-re-add cycles remain convergent`.

This is a worktree-to-main integration contract, not a fresh implementation rollout and not gap-closure. Reuse the source worktree row, source breakdown entry, source ML-008 plan, and source closure evidence as historical source of truth. Do not recreate, rewrite, or rerun the original worktree ML-008 implementation plan.

Allowed execution deltas are only row-owned, meaningful ML-008 deltas if main is missing or partially missing them:

- fake-network selector `ML-008 repeated add-remove-re-add cycles stay convergent across restarts`;
- `private_readd_cycles` criteria, runner, and harness support;
- `ml008CycleProof` emitted/validated for Alice/Bob/Charlie;
- criteria accept/reject tests for valid proof, missing proof, fewer than 20 cycles, insufficient restart markers, removed-window plaintext, missing post-readd delivery, and final divergence;
- ML-008 drain/cursor tests for deferred unknown-sender skip and cursorless final-page synthetic high-water persistence;
- bridge/native cursor retry tests for transient EOF/reset/timeout retry and synthetic `mknoon-since-ms:` cursor handling;
- only the minimal production deltas needed for the source-proven cursor/retry behavior if those deltas are not already present in main.

Do not import generic GM coverage as ML-008. Do not import ML-009, duplicate stale removal, history, notification, media, key-epoch, or broader churn scopes.

## closure bar

This plan is complete when an executor can safely decide one of these outcomes for ML-008 only:

- `skipped_already_present`: all meaningful ML-008 anchors and required cursor/retry behavior are already present in main, and the focused/source plus overlap preservation selectors pass or have accepted unrelated known-failure classification.
- `accepted`: missing or partial row-owned ML-008 deltas were integrated, focused/source plus overlap preservation selectors pass or have accepted unrelated known-failure classification, source-proven cursor/retry production deltas are imported only if missing, and the main integration ledger can be updated for INTEGRATE-ML-008 only.
- `blocked_conflict` or `blocked_external_fixture`: exact blockers are recorded without moving to ML-009.

This plan itself is not accepted evidence. Its status is `execution-ready`.

## source of truth

Authoritative sources for execution, in order:

1. Current main checkout code and tests, including existing dirty changes. Do not revert or overwrite unrelated edits.
2. Main integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`.
4. Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`.
5. Source ML-008 plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md`.
6. Main COMPLETE_1 overlap breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

COMPLETE_1 overlap rows own their own main coverage. They are preservation constraints, not source import targets for ML-008.

## session classification

`implementation-ready` integration contract.

The execution status must start as `execution-ready`, not `accepted`. It can become accepted only after a later executor performs the pre-application inspection, applies any missing/partial ML-008 deltas, and runs the required proof.

## exact problem statement

Source ML-008 already proved 20 repeated add/remove/re-add cycles with restart pressure, active member/key convergence after every cycle, Charlie post-readd entitlement, and zero Charlie removed-window plaintext. The source proof also exposed real replay/cursor/retry pressure gaps that were fixed narrowly in the source worktree.

Main has COMPLETE_1 coverage for adjacent remove/re-add and duplicate/idempotence behavior, but INTEGRATE-ML-008 is still pending in the main integration breakdown. Risk during integration: blindly importing source ML-008 could duplicate GM-022 20-cycle duplicate-free proof, GM-009 duplicate-remove proof, GM-010 duplicate-readd proof, GM-024 display/state proof, or later source rows. Execution must first determine whether ML-008 changes are already present in main, partially present, or missing.

## source ML-008 evidence

Source row exact contract:

| row | scenario | precondition | actions | expected |
|---|---|---|---|---|
| `ML-008` | Repeated add-remove-re-add cycles remain convergent | A, B, and C are valid peers. | Run 20 cycles of add C, send, remove C, send, re-add C, send; restart one peer every few cycles. | All active members agree after every cycle; C receives every entitled post-readd message and none from removed windows. |

Exact historical evidence from the source row and source plan:

- Covered on 2026-05-12 by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md`.
- `group_membership_smoke_test.dart` added `ML-008 repeated add-remove-re-add cycles stay convergent across restarts`, proving 20 repeated add/remove/re-add cycles, active member/key convergence after every cycle, restart markers, Charlie post-readd entitlement, and zero Charlie removed-window plaintext.
- `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_real_harness.dart`, and `run_group_multi_party_device_real.dart` require/emit `private_readd_cycles` `ml008CycleProof` fields and reject missing proof, fewer than 20 cycles, too few restart markers, removed-window plaintext leaks, missing post-readd delivery, and final epoch divergence.
- Source proof exposed and fixed narrow repo-owned replay pressure gaps: removed-member fanout includes the removed peer plus remaining active peers, group inbox drain preserves durable synthetic high-water cursors for cursorless final pages, drain skips deferred unknown-sender replay without blocking progress, Flutter/Go cursor retrieval retry transient relay EOF/reset/timeout failures, and the live harness wires cursor transaction hooks.
- Required source evidence passed: ML-008 fake-network selector (`+1`), `private_readd_cycles` criteria selector (`+6`), drain/cursor focused selectors, bridge transient EOF retry and timeout selectors, Go cursor/retry selectors, scoped harness analyzer with only pre-existing style infos, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` (`+133` after recovery cursor expectation update), `./scripts/run_test_gates.sh completeness-check` (`732/732`), exact-relay live `private_readd_cycles` run `1778539960629`, and `git diff --check`.
- Source live proof path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_cycles_Rqmx5B`.
- Source live app peers: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.
- Source live verdicts recorded 20 cycles for all roles, Alice `restartMarkersObserved=4`, Bob/Charlie `restartMarkersPerformed=2` each, final epoch `21`, final member lists including Alice/Bob/Charlie, Alice/Bob/Charlie post-readd delivery counts of 20, Bob removed-window receipt count of 20, Charlie self-removal count of 20, and Charlie `removedWindowPlaintextCount=0`.
- Source gates found and fixed one stale recovery cursor-count expectation: `group_resume_recovery_test.dart` was updated to assert the durable `mknoon-since-ms:` cursor.

Exact source ML-008 implementation/proof touched files:

- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `go-mknoon/node/group_inbox_test.go`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Exact source ML-008 production/support files named by the source plan after replay pressure gaps:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/node.go`

Historical source closure docs updated after proof, not import targets:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md`

## COMPLETE_1 overlap comparison

| COMPLETE_1 row | overlap with ML-008 | execution rule |
|---|---|---|
| `GM-022` | 20 remove/re-add cycles, duplicate-free raw/config member IDs, one active Charlie entry/device, active validator lookup, exact-once post-cycle delivery, unique durable recipients. | Preserve GM-022. Do not import or relabel its `gm022` proof as ML-008; ML-008 needs `private_readd_cycles` and removed-window/post-readd entitlement proof. |
| `GM-009` | Duplicate remove idempotence, at-most-once rotation/distribution, Charlie exclusion, A/B post-removal delivery. | Preserve GM-009. Do not import duplicate-remove idempotence or same-event removal guards as ML-008 unless focused ML-008 tests expose a real missing dependency. |
| `GM-010` | Duplicate re-add idempotence, one Charlie member/device binding, duplicate join prevention, durable-recipient uniqueness. | Preserve GM-010. Do not import duplicate-readd no-op proof as ML-008; repeated ML-008 cycles are not the same as duplicate identical re-add. |
| `GM-024` | Member display/state convergence for re-added C and authoritative snapshot `joinedAt` recovery. | Preserve GM-024. Do not import display/state or snapshot `joinedAt` recovery as ML-008 unless an ML-008-focused selector proves the exact source-proven cursor/retry behavior needs it. |

The main integration breakdown maps `ML-008` to `GM-022`, `GM-009`, `GM-010`, and `GM-024` as high-risk overlap rows. Current marker scan in main found no `ML-008`, `private_readd_cycles`, or `ml008CycleProof` anchors in code/test/harness files, but execution must still perform the file-by-file checklist below before importing.

## files and repos to inspect next

Pre-application inspection must compare source and main for these exact files before any import:

- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `go-mknoon/node/group_inbox_test.go`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/node.go`

Inspect these COMPLETE_1 overlap owner files before changing shared surfaces:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## pre-application inspection checklist

Before applying any source hunk, execution must:

1. Run `git status --short` and record existing dirty files. Do not revert unrelated dirty work.
2. For each exact source-touched file, inspect local main changes with `git diff -- <file>` and preserve user/controller edits.
3. Search each main file for `ML-008`, `private_readd_cycles`, `ml008CycleProof`, `readd cycles`, `mknoon-since-ms:`, `groupInboxSyntheticSinceCursorPrefix`, `transient relay`, `inboxRetrieveCursor`, and the source selector names.
4. Search each source file for the same anchors and identify exact source hunks.
5. Classify each file as `already_present`, `partial`, or `missing`.
6. If all ML-008 anchors and source-proven cursor/retry behavior are already present, skip importing and run focused proof only.
7. If partial, import only missing ML-008-specific anchors and reconcile with existing main helpers.
8. If missing, import only row-owned meaningful ML-008 hunks from the exact source files listed above.
9. For production files, import only minimal deltas tied to source-proven cursor/retry behavior and only if current main lacks them.
10. Do not import generic GM-006, GM-007, GM-009, GM-010, GM-022, or GM-024 proof as ML-008.
11. Do not import ML-009, ML-011, rapid ordering, duplicate stale removal, history, notification, media, key-epoch, broader churn, or later source rows.
12. Do not update source worktree docs or COMPLETE_1 docs during this integration row.

## existing tests covering this area

Main COMPLETE_1 already covers adjacent remove/re-add behavior:

- `GM-022` duplicate-free member/config state after 20 remove/re-add cycles.
- `GM-009` duplicate remove idempotence.
- `GM-010` duplicate re-add idempotence.
- `GM-024` member display/state convergence for re-added C.

These are preservation coverage only. They do not replace ML-008's row-owned `private_readd_cycles` proof, removed-window plaintext exclusion across 20 cycles, restart-marker contract, or source-proven replay/cursor/retry regressions.

## regression/tests to add first

Add nothing from scratch until the pre-application checklist classifies the ML-008 deltas. If missing or partial, import only these source-owned regressions/proof surfaces:

- fake-network/private-matrix selector named `ML-008 repeated add-remove-re-add cycles stay convergent across restarts`;
- `private_readd_cycles` scenario support in criteria, runner, and harness;
- `ml008CycleProof` emitted for Alice/Bob/Charlie with `rowId: ML-008`;
- criteria tests that accept valid proof and reject missing proof, fewer than 20 cycles, insufficient restart markers, Charlie removed-window plaintext, missing post-readd delivery, and final divergence;
- drain/cursor selectors named `ML-008 deferred unknown sender group replay is skipped without blocking cursor progress` and `ML-008 cursorless final page stores timestamp high-water instead of clearing progress`;
- bridge helper selectors named `reconnects and retries transient relay EOF cursor failures`, `transient cursor EOF shrinks page size before retrying oversized replay pages`, and the existing timeout selector for `group:inboxRetrieveCursor`;
- Go selectors for transient relay EOF retry and synthetic since-cursor retrieval.

## step-by-step implementation plan

1. Perform the pre-application inspection checklist.
2. Classify the row as already present, partial, or missing.
3. If already present, do not import. Run the focused ML-008 commands and overlap preservation selectors.
4. If partial, import only the missing ML-008 anchors and missing source-proven cursor/retry deltas.
5. If missing, import only row-owned ML-008 proof, tests, harness/runner/criteria, and minimal cursor/retry production hunks from the source files listed above.
6. Keep COMPLETE_1 GM-022/GM-009/GM-010/GM-024 owner behavior intact; when a shared file is touched, run the matching preservation selectors.
7. Run focused ML-008 commands.
8. Run affected COMPLETE_1 overlap preservation selectors based on touched shared files.
9. If criteria/runner/harness support was imported or changed, run the live `private_readd_cycles` proof.
10. Run named gates and hygiene.
11. Update only minimal main integration docs for INTEGRATE-ML-008 after proof. Do not move to ML-009 in this row.

## risks and edge cases

- Main has extensive dirty work; source hunks must not overwrite unrelated edits.
- COMPLETE_1 GM-022 already has 20-cycle duplicate-free proof, but ML-008 needs its own repeated entitlement/restart proof and must not alias GM-022.
- Cursorless final pages must preserve durable synthetic high-water state instead of clearing progress.
- Deferred unknown-sender replay must not block cursor progress.
- Transient relay EOF/reset/timeout during cursor retrieval must retry without masking non-transient failures.
- Charlie must receive all entitled post-readd messages and zero removed-window plaintext across all 20 cycles.
- Production file `group_info_wired.dart` is named in source ML-008 touched files, but execution must import it only if the exact hunk is row-owned and necessary for ML-008 source-proven behavior.

## exact tests and gates to run

Focused ML-008 source commands:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_cycles'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-008'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'reconnects and retries transient relay EOF cursor failures'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'transient cursor EOF shrinks page size before retrying oversized replay pages'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'BB-013 group:inboxRetrieveCursor timeout rethrows TimeoutException'
(cd go-mknoon && go test ./node -run 'TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF|TestGroupInboxRetrieveWithCursorResult_SyntheticSinceCursorUsesTimestampRetrieve|TestST004GroupInboxRetrieveSyntheticCursorKeepsInclusiveRelayBoundary' -count=1)
```

Affected COMPLETE_1 preservation selectors:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-022'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-022'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-022'
(cd go-mknoon && go test ./node -run 'TestGM022|TestFindMember_DuplicatePeerId|TestGroupTopicValidator' -count=1)
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-009'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010 re-adds C twice idempotently, keeps one device binding, and preserves A/B/C delivery'
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'GM-010'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate member_added'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate members_added'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-010'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
```

Required named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Required live proof if `private_readd_cycles` criteria/runner/harness support is imported or changed:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_cycles -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245
```

## known-failure interpretation

- If `./scripts/run_test_gates.sh completeness-check` reports only the unrelated existing fake classification gap seen in recent integration rows (`test/shared/fakes/fake_group_pubsub_network_test.dart`, `732/733`), classify it as unrelated/pre-existing and do not patch it in ML-008.
- Any failure in the new ML-008 smoke, `private_readd_cycles` criteria, drain/cursor, bridge retry, or Go cursor/retry selectors is ML-008-owned until triaged.
- Any GM overlap selector failure caused by shared ML-008 imports must be fixed before acceptance.
- A missing or unavailable iOS 26.2 live-device fixture blocks live proof; do not replace it with physical iOS, Android, macOS, Chrome, or a non-iOS-26.2 app peer.
- Existing dirty files are not failures unless ML-008 execution edits or breaks them.

## done criteria

- The executor records whether ML-008 was already present, partial, or missing in main.
- Missing/partial imports are limited to row-owned ML-008 deltas in the exact source-touched files.
- Production imports are limited to source-proven cursor/retry behavior and are skipped when already present.
- Focused ML-008 fake-network, criteria, drain/cursor, bridge retry, and Go cursor/retry selectors pass.
- Affected COMPLETE_1 preservation selectors for GM-022, GM-009, GM-010, and GM-024 pass or have accepted unrelated known-failure classification.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass or have accepted unrelated known-failure classification.
- Live `private_readd_cycles` proof passes if criteria/runner/harness are imported or changed.
- Minimal main integration docs are updated for INTEGRATE-ML-008 only.
- ML-009 remains untouched.

## scope guard

Do not duplicate COMPLETE_1 overlap coverage already present in main. Do not import generic `GM-006`, `GM-007`, `GM-009`, `GM-010`, `GM-022`, or `GM-024` proof as ML-008.

Explicit non-goals:

- `ML-009` rapid remove/re-add ordering.
- `ML-011` duplicate/stale removal.
- history retention and removed-window history policy beyond ML-008's zero Charlie removed-window plaintext proof.
- notification, media, key-epoch, reactions, timeline-truth, invite-state, or broader churn rows.
- generic GM duplicate-member/config normalization unless a focused ML-008 test proves the exact missing dependency.
- GM-024 display/state or authoritative snapshot `joinedAt` recovery unless a focused ML-008 test proves the exact missing dependency.
- source worktree doc updates.
- COMPLETE_1 doc updates.

## accepted differences / intentionally out of scope

- COMPLETE_1 GM rows remain their own accepted historical coverage and must not be reclosed by ML-008.
- Source ML-008 used the accepted multi-party harness prerequisite, but this integration row must still run its own live proof if harness/criteria/runner surfaces are imported or changed.
- Source ML-008 live proof used specific iOS 26.2 simulators; execution may block on live fixture availability rather than weaken the proof shape.
- Adjacent source rows layered onto `private_readd_cycles`, `private_rapid_readd`, `private_duplicate_remove`, history, media, notification, key, and churn scenarios remain out of scope.

## dependency impact

INTEGRATE-ML-009 remains the next pending row only after INTEGRATE-ML-008 is accepted, skipped as already present, or blocked with a concrete blocker. Do not advance to ML-009 during ML-008 planning or execution.

## reviewer findings

- Sufficiency: sufficient for execution as a minimal integration contract.
- Missing files, tests, or gates: none structurally missing; the executor must inspect exact source-touched files before import and run the listed focused/overlap commands.
- Stale assumptions: current marker scan suggests ML-008 is missing in main, but this is not enough to import blindly; file-by-file present/partial/missing classification is required.
- Overengineering: adjacent GM proof imports and later source-row scopes are explicitly blocked.
- Minimum needed: execute the checklist, import only missing row-owned deltas, run proof, and update minimal integration docs.

## arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred: exact hunk selection is deferred to execution after the pre-application inspection.

Accepted differences intentionally left unchanged: COMPLETE_1 overlap rows stay separate; source ML-008 closure evidence is historical and not rerun during planning.

Why this plan is safe to implement now: it is bounded to one integration row, names exact source evidence and touched files, protects dirty main work through pre-application inspection, requires overlap preservation selectors, and restricts production imports to source-proven cursor/retry behavior only when missing.

## blockers

None for planning. Execution may still block on same-file dirty conflicts or unavailable iOS 26.2 live proof fixtures.

## Execution Progress

- 2026-05-17T21:45:42+02:00 - Controller extracted execution contract. Files inspected: this INTEGRATE-ML-008 plan, skill contract, and dirty worktree summary. Decision/blocker: proceed with spawned Executor then spawned QA Reviewer via local `codex exec`; scope remains ML-008 only and the integration breakdown ledger will not be updated. Next action: spawn Executor for pre-application inspection, row-owned import/reconcile if needed, required verification, and plan verdict draft.
- 2026-05-17T21:56:44+02:00 - Executor pre-application inspection completed. Files inspected: exact source-touched ML-008 file list, current dirty worktree, source ML-008 row/source breakdown/source ML-008 plan evidence, main integration breakdown, and COMPLETE_1 overlap rows `GM-022`, `GM-009`, `GM-010`, `GM-024`. Decision/blocker: ML-008 is partial/missing in main, not `skipped_already_present`; main marker scan found no `ML-008`, `private_readd_cycles`, `ml008CycleProof`, `groupInboxSyntheticSinceCursorPrefix`, `mknoon-since-ms:`, source bridge retry selector, source Go synthetic cursor selector, or `groupInboxRecoverHook` anchors in the exact row-owned files. Source worktree contains those row-owned anchors and source evidence marks ML-008 accepted. COMPLETE_1 overlap rows are accepted preservation constraints only; no GM overlap proof will be imported or relabeled as ML-008. Next action: import only missing ML-008 proof/harness/test anchors and minimal source-proven cursor/retry production deltas.

### Executor Pre-Application Classification

| file | classification | evidence | ML-008 action |
|---|---|---|---|
| `test/features/groups/integration/group_membership_smoke_test.dart` | `missing` | main has no `ML-008`/`readd cycles` marker; source has `ML-008 repeated add-remove-re-add cycles stay convergent across restarts`. | Import only ML-008 20-cycle fake-network selector. |
| `integration_test/scripts/group_multi_party_device_criteria.dart` | `missing` | main has no `private_readd_cycles` or `ml008CycleProof`; source has requirement/dispatch/validator for `private_readd_cycles`. | Import only `private_readd_cycles` criteria support and ML-008 validator. |
| `test/integration/group_multi_party_device_criteria_test.dart` | `missing` | main has no `private_readd_cycles` selector/helper; source has accept/reject ML-008 proof tests. | Import only ML-008 criteria tests/helper. |
| `integration_test/scripts/run_group_multi_party_device_real.dart` | `missing` | main runner has no `private_readd_cycles`; source runner maps/list-docs that scenario. | Import only runner scenario mapping/list text for `private_readd_cycles`. |
| `integration_test/group_multi_party_device_real_harness.dart` | `missing` | main harness has no `private_readd_cycles`, `ML-008`, or `ml008CycleProof`; source has role routing and Alice/Bob/Charlie ML-008 proof emitters. | Import only ML-008 harness role route and proof flow. |
| `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `missing` | main has no ML-008 drain selectors or synthetic cursor constant marker; source has two ML-008 drain/cursor tests. | Import only ML-008 drain/cursor selectors. |
| `test/core/bridge/bridge_group_helpers_test.dart` | `partial` | main retains existing cursor timeout coverage but lacks source transient EOF/adaptive replay retry selectors. | Import only the missing transient EOF and adaptive limit retry tests. |
| `go-mknoon/node/group_inbox_test.go` | `missing` | main has no source retry/synthetic selector names; source has three cursor/retry tests. | Import only ML-008 source-proven Go cursor/retry selectors. |
| `test/features/groups/integration/group_resume_recovery_test.dart` | `partial` | main has adjacent resume recovery coverage but lacks source synthetic cursor expectation update. | Update only the source-proven cursor-count/high-water expectation if needed by imported drain behavior. |
| `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` | `partial` | main has existing drain/cursor behavior but no `groupInboxSyntheticSinceCursorPrefix`/`mknoon-since-ms:` anchor. | Import only source-proven synthetic high-water and deferred unknown-sender progress behavior. |
| `lib/core/bridge/bridge_group_helpers.dart` | `partial` | main has cursor retrieval and timeout handling but lacks source transient relay EOF/reset retry and adaptive page-limit behavior. | Import only source-proven cursor retry/adaptive limit helpers. |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | `already_present` | source and main scans show no ML-008-owned cursor/retry/harness marker in this file. | No change. |
| `go-mknoon/node/group_inbox.go` | `partial` | main has group inbox cursor retrieval but no synthetic cursor constant/retry wrapper markers. | Import only source-proven synthetic cursor handling and transient relay retry wrapper. |
| `go-mknoon/node/node.go` | `partial` | source uses `groupInboxRecoverHook` for retry test seam; main lacks the seam. | Add only the ML-008 row-owned retry test seam if Go retry tests are imported. |
- 2026-05-17T22:11:29+02:00 - Executor row-owned import completed and formatted. Files touched: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `go-mknoon/node/group_inbox_test.go`, `test/features/groups/integration/group_resume_recovery_test.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/group_inbox.go`, and `go-mknoon/node/node.go`; `lib/features/groups/presentation/screens/group_info_wired.dart` remains unchanged because no ML-008-owned source hunk was identified. Decision/blocker: imports stayed limited to ML-008 cycle proof, `private_readd_cycles` criteria/runner/harness support, ML-008 drain/cursor tests, transient cursor retry tests, synthetic high-water cursor behavior, and the Go retry test seam. `dart format` ran on touched Dart files, `gofmt` ran on touched Go files, and scoped `git diff --check` passed. Next action: run focused ML-008 selectors, Go cursor/retry selector, overlap preservation selectors, named gates, scenario list, and live proof if the device fixture is available.
- 2026-05-17T22:45:18+02:00 - Executor verification completed. Files touched remain the row-owned ML-008 files listed above; production files touched were limited to `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/group_inbox.go`, and `go-mknoon/node/node.go`; `lib/features/groups/presentation/screens/group_info_wired.dart` remains untouched. Decision/blocker: focused host selectors and overlap preservation selectors passed, but the required live `private_readd_cycles` proof failed twice at the same cycle-7 Bob membership re-add convergence point. Row verdict: `blocked_conflict`. Next safe action: investigate why Bob does not converge to the cycle-7 `members_added` inclusion before sending Alice post-readd cycle 7; do not move to ML-009 from this Executor result.

### Executor Verification Results

Focused ML-008 selectors:

- Passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_cycles'` (`+7`).
- Passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-008'` (`+2`).
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'reconnects and retries transient relay EOF cursor failures'`.
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'transient cursor EOF shrinks page size before retrying oversized replay pages'`.
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'BB-013 group:inboxRetrieveCursor timeout rethrows TimeoutException'`.
- Passed: `(cd go-mknoon && go test ./node -run 'TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF|TestGroupInboxRetrieveWithCursorResult_SyntheticSinceCursorUsesTimestampRetrieve|TestST004GroupInboxRetrieveSyntheticCursorKeepsInclusiveRelayBoundary' -count=1)`.
- Passed after ML-008-owned expectation adjustment for current main self-removal semantics: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-008'`. The first run expected Charlie's removed-window local group to remain non-null; current main deletes Charlie's local group on self-removal, so the ML-008 test now expects `null` during the removed window.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'long-offline mixed-window recovery keeps retained backlog and never resurrects expired pages'`.
- Passed: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios`; output included `private_readd_cycles`.

COMPLETE_1 overlap preservation:

- Passed GM-022 selectors in `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, `add_group_member_use_case_test.dart`, `member_removal_integration_test.dart`, `group_message_listener_test.dart`, and `(cd go-mknoon && go test ./node -run 'TestGM022|TestFindMember_DuplicatePeerId|TestGroupTopicValidator' -count=1)`.
- Passed GM-009 selectors in `group_membership_smoke_test.dart` and `group_multi_party_device_criteria_test.dart`.
- Passed GM-010 selectors in `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, and the two `group_message_listener_test.dart` duplicate member selectors. The plan's `add_group_member_use_case_test.dart --plain-name 'GM-010'` selector has no matching tests in current main and exited with "No tests ran"; the existing equivalent duplicate-add preservation selector `rejects duplicate member before sync and preserves original row` passed.
- Passed GM-024 selector in `group_membership_smoke_test.dart`.

Named gates and hygiene:

- `dart format` ran on touched Dart files; `gofmt` ran on touched Go files.
- Passed: scoped `git diff --check -- <touched ML-008 files>`.
- Passed: full `git diff --check`.
- Failed with accepted unrelated blocker evidence: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed only in `test/features/groups/integration/invite_round_trip_test.dart` for `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`. Standalone rerun of that selector failed the same way. Triage evidence: the test uses fixed `receivedAt = DateTime.utc(2026, 5, 10, 20)` and current date is 2026-05-17, placing the replay outside the 7-day retention window; this is outside ML-008.
- Failed with accepted known classification gap: `./scripts/run_test_gates.sh completeness-check` reported `732/733 test files classified` with only `test/shared/fakes/fake_group_pubsub_network_test.dart` unmatched.

Live `private_readd_cycles` proof:

- Attempt 1 on iOS 26.2 simulators Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, run id `1779049426301`, failed with runner exit 255. Alice timed out waiting for `gmp_1779049426301_bob_membership_readded_7`; Charlie timed out waiting for `gmp_1779049426301_alice_sent_ml008AlicePostReadd7.json`; Bob exited before writing a verdict. Shared-dir evidence had `bob_membership_readded_1` through `_6`, `alice_sent_ml008AlicePostReadd1.json` through `_6.json`, `charlie_group_rejoined_7`, and `charlie_readd_group_fixture_7`, but no cycle-7 Bob re-add signal.
- Attempt 2 on the same iOS 26.2 simulators, run id `1779050116627`, failed with the same shape. Alice published the cycle-7 `members_added` payload at key epoch 8 (`messageId` ending `1779050415028018`) and Charlie received it, but Bob only recorded `bob_membership_readded_1` through `_6`; Alice again timed out waiting for `gmp_1779050116627_bob_membership_readded_7`, Charlie timed out waiting for `gmp_1779050116627_alice_sent_ml008AlicePostReadd7.json`, and Bob exited before verdict.
- Live logs also contain relay/direct-dial `NO_RESERVATION` and `context deadline exceeded` events after Bob failed to converge, but the repeated deterministic block is Bob's missing cycle-7 membership inclusion after six successful cycles. This is classified as `blocked_conflict`, not `blocked_external_fixture`.

### Executor Scope Notes

- Skipped adjacent/later scopes: no ML-009 rapid ordering, duplicate stale removal, history retention, notification, media, key-epoch, security, observability, stress, broader churn, or later proof fields were imported.
- COMPLETE_1 overlap coverage was preserved and not duplicated as ML-008 ownership.
- Integration breakdown ledger, source worktree docs, COMPLETE_1 docs, source matrix docs, and unrelated plan docs were not updated by this Executor.

### Executor Verdict

`blocked_conflict`

The row cannot be accepted because the required live `private_readd_cycles` proof fails twice at the same ML-008 convergence point. Host/fake criteria, drain/cursor, bridge retry, Go cursor/retry, overlap preservation, formatting, and diff hygiene are otherwise recorded above.

### QA Reviewer Note

- 2026-05-17T22:48:01+02:00 - QA Reviewer pass approved the Executor's `blocked_conflict` verdict for INTEGRATE-ML-008. Reviewed the plan, Executor final summary, groups gate log, git status, full `git diff --check`, and targeted ML-008-owned diffs/anchors. The plan records file-by-file pre-application `missing`/`partial`/`already_present` classifications, row-scoped imports, required host/fake/criteria/drain/bridge/Go/overlap/gate evidence, scenario-list proof, and two live `private_readd_cycles` failures at Bob's cycle-7 membership re-add convergence point. No code changes were made by QA; source worktree docs, COMPLETE_1 docs, source matrix docs, integration breakdown ledger, and unrelated plan docs remain untouched. Verdict remains `blocked_conflict`; next retry should investigate Bob's missing `bob_membership_readded_7` convergence before ML-009.

## Focused Conflict Recovery

- 2026-05-17T23:49:00+02:00 - Recovery completed for INTEGRATE-ML-008 only. Root cause: the multi-member `members_added` system payload was live-published but not durably replay-stored for the updated member recipient set, so Bob could miss a re-add under repeated relay/offline drain pressure. Narrow fix: `integration_test/group_multi_party_device_real_harness.dart` now stores a `storeGroupOfflineReplayEnvelope` for `_publishMembersAddedSystemPayload` after the successful live publish, addressed to the updated member peer IDs; Bob also records an exact Charlie member-row proof after every re-add. Criteria/test hardening: `integration_test/scripts/group_multi_party_device_criteria.dart` requires `bobCharlieExactMemberRowCountProofs >= 20`; `test/integration/group_multi_party_device_criteria_test.dart` covers the rejection; `test/features/groups/integration/group_membership_smoke_test.dart` asserts exactly one row for each expected peer. No ML-009, history, notification, media, key-epoch, or broader churn deltas were imported.

Recovery verification:

- Passed: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-008'`.
- Passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_cycles'` (`+8`, including exact Bob member-row proof rejection).
- Passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-008'`.
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'reconnects and retries transient relay EOF cursor failures'`.
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'transient cursor EOF shrinks page size before retrying oversized replay pages'`.
- Passed: `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'BB-013 group:inboxRetrieveCursor timeout rethrows TimeoutException'`.
- Passed: `(cd go-mknoon && go test ./node -run 'TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF|TestGroupInboxRetrieveWithCursorResult_SyntheticSinceCursorUsesTimestampRetrieve|TestST004GroupInboxRetrieveSyntheticCursorKeepsInclusiveRelayBoundary' -count=1)`.
- Passed: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios`; output included `private_readd_cycles`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'long-offline mixed-window recovery keeps retained backlog and never resurrects expired pages'`.
- Passed preservation selectors for COMPLETE_1 rows `GM-022`, `GM-009`, `GM-010`, and `GM-024`; the current-main `add_group_member_use_case_test.dart --plain-name 'GM-010'` still has no matching test and the equivalent duplicate-add preservation selector `rejects duplicate member before sync and preserves original row` passed.
- Passed hygiene: `dart format` on the touched Dart files, `gofmt` on the touched Go files, scoped `dart analyze` on the four recovery Dart files, scoped `git diff --check`, and full `git diff --check`.

Fresh live proof:

- Passed: iOS 26.2 `private_readd_cycles` run id `1779053630154`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_cycles_PQj6qH`, devices Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `ok=true`, `detail="private_readd_cycles verdicts valid for alice, bob, charlie"`, file `gmp_1779053630154_private_readd_cycles_orchestrator_verdict.json`.
- Cycle-7 regression proof: `gmp_1779053630154_bob_membership_readded_7` exists before `gmp_1779053630154_alice_sent_ml008AlicePostReadd7.json` was written; cycle 20 also produced `gmp_1779053630154_bob_membership_readded_20` and `gmp_1779053630154_alice_sent_ml008AlicePostReadd20.json`.
- Bob verdict: `cycleCount=20`, `receivedRemovedWindowCount=20`, `receivedAlicePostReaddCount=20`, `receivedCharliePostReaddCount=20`, `bobCharlieExactMemberRowCountProofs=20`, `restartMarkersPerformed=2`, `finalMemberListIncludesAliceBobCharlie=true`, `finalEpoch=21`.
- Alice verdict: `removedWindowSendCount=20`, `sentPostReaddCount=20`, `receivedCharliePostReaddCount=20`, `restartMarkersObserved=4`, `finalMemberListIncludesAliceBobCharlie=true`, `finalEpoch=21`.
- Charlie verdict: `selfRemovalCount=20`, `receivedAlicePostReaddCount=20`, `postReaddSendCount=20`, `removedWindowPlaintextCount=0`, `restartMarkersPerformed=2`, `finalMemberListIncludesAliceBobCharlie=true`, `finalEpoch=21`.

### Recovery Verdict

`accepted`

Prior failed live proof runs `1779049426301` and `1779050116627` remain preserved above as historical blocked-conflict evidence, but are superseded for acceptance by recovery run `1779053630154`. Safe next pipeline action: resume at `INTEGRATE-ML-009`; this recovery did not execute or import ML-009.
