# INTEGRATE-ML-004 Worktree-to-Main Integration Contract

Status: execution-ready

Source row: `ML-004`, "Batch add with mixed success produces a truthful member set"

Mode: standard worktree-to-main integration. This is not gap-closure and is not a new implementation plan.

## Planning Progress

- 2026-05-17 19:03:32 CEST - Evidence Collector completed. Files inspected since last update: integration breakdown ML-004 ledger/contract, source matrix row ML-004, source breakdown session ML-004, historical ML-004 plan/evidence, COMPLETE_1 overlap searches, source/current test anchors. Decision/blocker: source ML-004 was tests-only in four test files plus docs; current main has no `ML-004` selectors but has overlapping `GM-036`/`GE-015` coverage. Next action: draft the minimal import/reconcile/verify contract.
- 2026-05-17 19:03:32 CEST - Planner started. Files inspected since last update: same evidence set. Decision/blocker: no blocker; contract must avoid recreating the original worktree implementation plan. Next action: write scoped integration sections with duplicate checks, likely imports, verification gates, and ledger policy.
- 2026-05-17 19:04:25 CEST - Planner completed. Files inspected since last update: source test anchors and COMPLETE_1 overlap rows. Decision/blocker: reusable minimal integration contract is drafted around compare/import/verify only. Next action: reviewer pass for missing scope, overlap, and gate details.
- 2026-05-17 19:04:25 CEST - Reviewer completed. Files inspected since last update: drafted contract sections. Decision/blocker: sufficient after explicitly preserving `GM-036` and `GE-015`, naming affected tests, and making production changes non-goal unless exact diff proves otherwise. Next action: arbiter finalizes readiness.
- 2026-05-17 19:04:25 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final contract. Decision/blocker: no structural blockers remain; this is execution-ready as a minimal integration contract. Next action: executor may reconcile ML-004 into main without touching source worktree files.

## Execution Progress

- 2026-05-17 19:07:22 CEST - Controller started contract extraction. Files inspected or touched: this plan, current `git status --short`, skill instructions. Command currently running: none. Decision/blocker: no blocker; `codex exec` is available for isolated Executor/QA subprocesses. Next action: extract scope/tests and spawn Executor.
- 2026-05-17 19:07:33 CEST - Contract extracted. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: exact scope is four ML-004 source anchors compared against four main test files; duplicate/overlap checks, focused `ML-004`, `GM-036`, `GE-015`, preservation tests, `groups`, `completeness-check`, and `git diff --check` are required when feasible; production edits remain out of scope unless exact ML-004 proof requires a narrow fix. Next action: spawn isolated Executor.
- 2026-05-17 19:07:57 CEST - Executor spawned/running. Files inspected or touched: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: no blocker. Next action: Executor performs duplicate checks, compares four source anchors, imports only missing meaningful ML-004 deltas, and runs focused/preservation tests.
- 2026-05-17 19:08:30 CEST - Executor spawn retry. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: first spawn command exited before child work because CLI approval flag placement was invalid; no code/test files were touched by the failed child. Next action: retry Executor with top-level approval flag and the same isolated contract.
- 2026-05-17 19:09:27 CEST - Executor started pre-inspection heartbeat. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: no blocker; proceeding only with ML-004 row-owned files and exact duplicate/overlap checks. Next action: run `git status --short` and required `rg` overlap scans.
- 2026-05-17 19:09:52 CEST - Duplicate/overlap checks completed. Files inspected or touched: this plan, four main ML-004 candidate test files, COMPLETE_1 breakdown. Commands completed: `git status --short`; `rg -n "ML-004" ...`; `rg -n "GM-036|GE-015|needsResend|send_failed|mixed invite|batch invite" ...`; `rg -n "GM-036|GE-015|create_group_with_members_use_case_test\.dart|contact_picker_wired_test\.dart|group_info_wired_test\.dart|group_membership_smoke_test\.dart" ...COMPLETE_1-session-breakdown.md`. Decision/blocker: no current main `ML-004` selectors found; GM-036 overlap appears in contact picker, group info, and membership smoke; GE-015 and GM-036 are documented in COMPLETE_1. Next action: inspect source anchors and matching main files.
- 2026-05-17 19:12:03 CEST - Owner-file inspection completed; import/reconcile starting. Files inspected or touched: four source ML-004 anchors, four matching main test files, main/source fixture helpers. Command currently running: none. Decision/blocker: no blocker; all four source anchors add row-owned ML-004 value beyond current main overlap, with only minimal fixture glue needed in the create use-case test. Next action: import the four ML-004 selectors into matching main test files.
- 2026-05-17 19:14:49 CEST - Import/reconcile completed. Files inspected or touched: this plan plus four matching main test files. Commands completed: `dart format` on the four touched tests; post-import `rg -n "ML-004" ...`. Decision/blocker: no blocker; four ML-004 selectors are now present in main. Next action: run focused ML-004 selectors.
- 2026-05-17 19:15:05 CEST - Focused test pass started. Files inspected or touched: this plan and four touched test files. Command currently running: focused ML-004 `flutter test --no-pub` selectors. Decision/blocker: no blocker. Next action: run the five required ML-004 selector commands.
- 2026-05-17 19:16:08 CEST - Focused ML-004 selectors passed. Files inspected or touched: four touched test files. Commands completed: the four per-file ML-004 `flutter test --no-pub --plain-name 'ML-004'` selectors plus the combined four-file ML-004 selector. Decision/blocker: no blocker. Next action: run GM-036/GE-015 overlap selectors.
- 2026-05-17 19:17:00 CEST - Overlap selectors completed. Files inspected or touched: contact picker, group info, membership smoke tests. Commands completed: contact-picker `GM-036` passed; group-info `GM-036` passed; membership-smoke `GM-036` passed; contact-picker `GE-015` returned exit 79 with `No tests ran. No tests match "GE-015"` and `rg -n "GE-015" test/features/groups/presentation/contact_picker_wired_test.dart` found no selector. Decision/blocker: GE-015 selector absence appears pre-existing and not introduced by ML-004 import; continue with preservation suites for row-owned files. Next action: run four whole-file preservation tests, gates, and diff hygiene.
- 2026-05-17 19:18:07 CEST - Whole-file preservation tests passed. Files inspected or touched: four touched test files. Commands completed: whole `create_group_with_members_use_case_test.dart` passed; whole `contact_picker_wired_test.dart` passed; whole `group_info_wired_test.dart` passed; whole `group_membership_smoke_test.dart` passed. Decision/blocker: no row-owned blocker. Next action: run `groups`, `completeness-check`, and `git diff --check`.
- 2026-05-17 19:20:08 CEST - Groups gate passed. Files inspected or touched: four touched test files plus gate-owned group tests invoked by `./scripts/run_test_gates.sh groups`. Commands completed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` exited 0 with final `All tests passed!`. Decision/blocker: no row-owned blocker. Next action: run `completeness-check` and `git diff --check`.
- 2026-05-17 19:20:35 CEST - Final gate sweep completed. Files inspected or touched: this plan and four touched test files; `git status --short` also showed pre-existing unrelated dirty files. Commands completed: `./scripts/run_test_gates.sh completeness-check` failed with `Completeness check: 732/733 test files classified` and unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`; `git diff --check` passed. Decision/blocker: completeness failure is outside ML-004 row-owned files and was not introduced by the ML-004 import. Next action: write executor handoff.
- 2026-05-17 19:23:00 CEST - Executor handoff completed; QA review starting. Files inspected or touched: this plan and current `git status --short`. Command currently running: none. Decision/blocker: no executor-reported row-owned blocker; QA must scrutinize GE-015 selector absence and unrelated completeness-check classification before final verdict. Next action: spawn isolated QA Reviewer.
- 2026-05-17 19:25:49 CEST - QA Reviewer started independent review. Files inspected or touched: this plan, four target-file ML-004 diffs, four source-worktree ML-004 anchors. Commands completed: source/current anchor inspections and `rg -n "ML-004|GM-036|GE-015" ...`. Decision/blocker: no blocker found; the four source anchors were imported with only main-helper adaptation in contact picker, and current main now has one row-owned ML-004 selector per target file. Next action: run required lightweight QA verification commands and classify non-green executor items.
- 2026-05-17 19:26:05 CEST - QA Reviewer completed. Files inspected or touched: this plan, four target test files, `test/shared/fakes/fake_group_pubsub_network_test.dart` status. Commands completed: required `rg -n "ML-004" ...`; required `rg -n "GE-015" test/features/groups/presentation/contact_picker_wired_test.dart`; required combined four-file `flutter test --no-pub ... --plain-name 'ML-004'`; required `git diff --check`; provenance checks `git show HEAD:...contact_picker_wired_test.dart | rg -n "GE-015"`, `git diff -- contact_picker_wired_test.dart | rg -n "GE-015|ML-004"`, and `git status --short -- test/shared/fakes/fake_group_pubsub_network_test.dart`. Decision/blocker: verdict pass; GE-015 selector absence and completeness unmatched fake file are accepted as external/pre-existing, not ML-004 blockers. Next action: final session status can be `accepted`.
- 2026-05-17 19:27:13 CEST - Final verdict writing started. Files inspected or touched: this plan and QA handoff. Command currently running: none. Decision/blocker: no QA blocker; write final status `accepted` and preserve ledger for closure/controller verification. Next action: append `## Final Execution Verdict`.
- 2026-05-17 19:27:30 CEST - Final verdict written. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: session status `accepted`; integration breakdown ledger intentionally not updated per current user instruction. Next action: final controller verification and response.

## real scope

Import or reconcile exactly `INTEGRATE-ML-004` from the source worktree into main. The only row behavior owned here is: when A batch-adds B, C, and D and one invite/config-publish path fails, only successfully onboarded members are treated as active, while the failed recipient remains visibly failed or retryable rather than silently joined.

Production changes are expected to be none unless an exact source-to-main diff proves a missing ML-004 behavior gap that cannot be covered by the current main implementation. Historical ML-004 source evidence was tests-only in four test files plus source docs; no production files changed in the accepted source worktree session.

Do not recreate, rewrite, or rerun the original worktree implementation plan. Use the historical plan and closure evidence only as source-of-truth input for this import contract.

## closure bar

ML-004 integration is good enough when main either already has, or receives, row-owned proof that:

- a mixed B/C/D batch with one forced invite delivery failure preserves truthful DB member rows, Go/config payloads, invite attempts, and visible member list state;
- Bob/Charlie successful delivery paths remain acceptable while Dave stays failed/pending retry and not `Joined`;
- current COMPLETE_1/main overlap rows, especially `GM-036` and `GE-015`, still pass;
- no product or harness behavior is changed unless a precise conflict demands it and is recorded as a row-owned exception.

## source of truth

Authoritative inputs, in precedence order:

1. Main code and tests after existing dirty changes are respected.
2. Integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source worktree row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `ML-004`.
4. Source worktree session: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `ML-004`.
5. Historical source plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-004-plan.md`.
6. Main overlap artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

If docs conflict, executable tests and current main behavior win over stale prose, but the source ML-004 row title and accepted evidence define the row-owned import boundary.

## session classification

`implementation-ready` for integration execution only. This means compare/import/verify is ready; it does not authorize a new feature implementation plan.

## exact problem statement

The source worktree accepted ML-004 on 2026-05-11 with host tests proving mixed-success batch invite truthfulness. Main currently has no `ML-004` selectors in the four candidate proof files, but COMPLETE_1 has overlapping mixed-invite coverage in `GM-036` and related pending/repair coverage in `GE-015`. The integration risk is either missing the ML-004 create/add/visible/acceptance proof in main or duplicating existing `GM-036` assertions without adding row-owned value.

The executor must reconcile the source ML-004 tests into main only where they provide missing meaningful coverage.

## changed-file inventory from source evidence

Historical ML-004 source evidence says the accepted worktree session changed these row-owned test files:

- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/create_group_with_members_use_case_test.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/presentation/contact_picker_wired_test.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/presentation/group_info_wired_test.dart`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/integration/group_membership_smoke_test.dart`

Historical source docs updated during closure, but they are evidence only and must not be copied into main:

- source matrix row `ML-004`
- source session breakdown `ML-004`
- source `test-inventory.md`
- source historical ML-004 plan

## duplicate/overlap checks to perform

Before editing, run these checks in main:

```bash
git status --short
rg -n "ML-004" test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart
rg -n "GM-036|GE-015|needsResend|send_failed|mixed invite|batch invite" test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart
rg -n "GM-036|GE-015|create_group_with_members_use_case_test\.dart|contact_picker_wired_test\.dart|group_info_wired_test\.dart|group_membership_smoke_test\.dart" Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md
```

Source ML-004 anchors to compare, not wholesale-copy:

- `create_group_with_members_use_case_test.dart`: `ML-004 mixed B/C/D invite failure preserves truthful create roster and invite state`
- `contact_picker_wired_test.dart`: `ML-004 existing-group mixed B/C/D invite failure preserves truthful picker state`
- `group_info_wired_test.dart`: `ML-004 mixed B/C/D invite state shows failed recipient as resendable, not joined`
- `group_membership_smoke_test.dart`: `ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending`

Known COMPLETE_1/main overlaps to preserve:

- `GM-036 batch invite reports mixed delivery after local re-add`
- `GM-036 mixed invite statuses remain visible after reload`
- `GM-036 send after mixed re-add does not clear failed invite status`
- `GE-015` contact-picker pending/repair behavior in `contact_picker_wired_test.dart`

## likely files to import

Likely import/reconcile targets in main:

- `test/features/groups/application/create_group_with_members_use_case_test.dart`: likely import the ML-004 create-with-members proof if still absent; no same-file COMPLETE_1 duplicate was found.
- `test/features/groups/presentation/contact_picker_wired_test.dart`: compare carefully against `GM-036` and `GE-015`; import only the distinct ML-004 existing-group B/C/D add proof if it adds source-row value beyond mixed re-add feedback.
- `test/features/groups/presentation/group_info_wired_test.dart`: compare against `GM-036`; import only if ML-004 adds distinct "failed Dave not joined" and successful-member overlay coverage.
- `test/features/groups/integration/group_membership_smoke_test.dart`: compare against `GM-036`; import only if ML-004 adds the delivered Bob/Charlie acceptance plus Dave no local group/pending join proof.

No production files are likely import targets.

## files and repos to inspect next

Inspect only these main files unless a direct conflict forces narrower supporting context:

- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- this integration contract

Supporting production files may be read for conflict understanding only, not edited by default:

- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`

## existing tests covering this area

Main currently has overlapping coverage:

- `GM-036` in `contact_picker_wired_test.dart`, `group_info_wired_test.dart`, and `group_membership_smoke_test.dart` proves mixed C/D invite delivery feedback after local re-add, visible failed invite status, and that a later send does not clear failed invite state.
- `GE-015` in COMPLETE_1 touches contact-picker pending/repair status and production hardening around durable pending invite fanout.
- Main has no `ML-004` selectors in the four candidate files at planning time.

## regression/tests to add first

Do not design new regressions from scratch. Reuse the accepted source ML-004 test blocks if and only if duplicate checks show they are missing or materially stronger than current main overlap.

If a source test conflicts with changed main helper APIs, adapt only the fixture glue needed for that test to compile while preserving the original assertion: truthful mixed-success membership state and no silent active/joined status for the failed recipient.

## step-by-step implementation plan

1. Reconfirm `git status --short`; preserve unrelated dirty files and do not revert anything.
2. Run the duplicate/overlap checks above.
3. Open the four source ML-004 test anchors and the four main target files.
4. For each candidate test, classify it as `already covered by main`, `import missing test`, or `blocked by conflict`.
5. Import only missing meaningful ML-004 test blocks into the matching main test file. Do not copy source docs.
6. If any imported test fails, first fix test fixture drift. Edit production only if an exact failing ML-004 assertion proves current main behavior is wrong and the fix can be limited to that seam.
7. Run focused ML-004 tests and affected COMPLETE_1/main overlap tests.
8. Update this plan with execution evidence and update the integration breakdown ledger for `INTEGRATE-ML-004` only.

## risks and edge cases

- Existing dirty files in this worktree may contain user or prior integration changes. Work with them; do not overwrite them with source-worktree versions.
- `GM-036` is close enough to invite duplication risk, but it is a re-add/admin-feedback row, not the ML-004 B/C/D create/add row. Treat it as overlap, not automatic replacement.
- Contact-picker behavior also overlaps with `GE-015`; preserve durable pending/repair status.
- 3-party E2E is recommended and unclaimed for ML-004. It is not a blocking device proof and must not pull this session into harness work.

## exact tests and gates to run

Focused ML-004 selectors after import/reconcile:

```bash
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'ML-004'
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'ML-004'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'ML-004'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-004'
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-004'
```

Affected COMPLETE_1/main overlap tests:

```bash
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'GM-036'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'GM-036'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-036'
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'GE-015'
```

Preservation/gates:

```bash
flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## known-failure interpretation

Any imported ML-004 selector failure is a blocker unless proven to be test-fixture drift from main evolution. `GM-036` or `GE-015` failures caused by the import are blockers for this integration session. Missing simulator/device/relay capacity is not an ML-004 blocker because 3-party E2E is recommended only.

If broad gates fail in unrelated pre-existing areas, record the exact failures, rerun all focused ML-004 and overlap selectors, and only proceed with reviewer approval if row-owned proof is green.

## done criteria

- Duplicate/overlap scan is recorded in this plan's execution notes.
- Each source ML-004 test anchor is classified as imported, already covered, or conflict-blocked.
- If imported, focused ML-004 selectors pass.
- Affected `GM-036` and `GE-015` overlap selectors pass or any pre-existing unrelated failure is clearly isolated.
- `groups`, `completeness-check`, and `git diff --check` pass, or known unrelated failures are documented with direct proof green.
- Integration breakdown ledger row `INTEGRATE-ML-004` is updated with final status and exact files/tests.

## scope guard

Do not edit source worktree files. Do not copy source closure docs into main. Do not touch product/test files outside the four likely test imports unless an exact ML-004 conflict requires a minimal test-helper adaptation. Do not import ML-005+, removal/re-add, key-epoch, media, notification, security, observability, stress, relay, or harness work. Do not run or require 3-party E2E as a blocking proof.

## accepted differences / intentionally out of scope

- Source ML-004 accepted host-side tests as sufficient; main may preserve that proof level.
- `GM-036` covers adjacent mixed invite feedback after re-add but does not automatically close ML-004 unless the executor proves the same row contract is already present.
- 3-party E2E remains recommended/unclaimed for ML-004 and is intentionally non-blocking.
- Production changes are intentionally out of scope unless exact diff and focused test failure prove otherwise.

## dependency impact

The next integration session is `INTEGRATE-ML-005`. It should not start until `INTEGRATE-ML-004` is `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture` in the integration breakdown ledger.

Later membership lifecycle integrations may rely on ML-004 only after the ledger records exact row evidence or a skip rationale tied to current main tests.

## final ledger update policy

After execution, update only:

- this plan file with execution evidence/final verdict;
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md` row and closure ledger for `INTEGRATE-ML-004`.

Use these statuses:

- `accepted`: missing meaningful ML-004 coverage was imported/reconciled and verified.
- `skipped_already_present`: no import was needed because main already proved the ML-004 row contract; record exact selectors and overlap rows.
- `blocked_conflict`: source ML-004 coverage conflicts with current main behavior or COMPLETE_1 rows and cannot be safely reconciled in this session.
- `blocked_external_fixture`: verification is impossible due to a fixture/environment blocker that is not row-owned. Do not use this for missing 3-party E2E.

Do not update source worktree files, source matrix docs, COMPLETE_1 docs, or final program verdict unless the integration breakdown policy explicitly requires it after all rows are resolved.

## reviewer pass

Sufficiency: sufficient as-is for integration execution. Missing files/tests/gates were narrowed to the four source test anchors, `GM-036`/`GE-015` overlap checks, focused selectors, preservation tests, `groups`, `completeness-check`, and `git diff --check`. No structural overreach remains because the contract forbids new implementation planning and production changes by default.

## arbiter decision

No structural blockers remain. Incremental details intentionally deferred to the executor: exact block-level import mechanics and fixture adaptation, because they depend on current main file state at execution time. Accepted difference: recommended 3-party E2E is not required or blocking for ML-004.

## Executor Handoff

Timestamp: 2026-05-17 19:21:04 CEST.

Changed files:

- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-004-plan.md`

Anchor classifications:

- `create_group_with_members_use_case_test.dart` source anchor `ML-004 mixed B/C/D invite failure preserves truthful create roster and invite state`: imported; main had no ML-004 selector and the imported test proves truthful roster/invite status when one recipient's invite fails.
- `contact_picker_wired_test.dart` source anchor `ML-004 existing-group mixed B/C/D invite failure preserves truthful picker state`: imported; main had no ML-004 selector and the imported test proves failed recipient remains resendable while successful recipients are not reselected.
- `group_info_wired_test.dart` source anchor `ML-004 mixed B/C/D invite state shows failed recipient as resendable, not joined`: imported; main had no ML-004 selector and the imported test proves UI status truthfulness for delivered versus failed invitees.
- `group_membership_smoke_test.dart` source anchor `ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending`: imported; main had no ML-004 selector and the imported smoke test proves delivered recipients can accept while the failed recipient remains pending.

Commands/results:

- Duplicate/overlap checks passed as inspection evidence: `git status --short`; `rg -n "ML-004" ...`; `rg -n "GM-036|GE-015|needsResend|send_failed|mixed invite|batch invite" ...`; `rg -n "GM-036|GE-015|create_group_with_members_use_case_test\.dart|contact_picker_wired_test\.dart|group_info_wired_test\.dart|group_membership_smoke_test\.dart" ...COMPLETE_1-session-breakdown.md`.
- `dart format` on the four touched test files passed.
- Focused ML-004 selectors passed: four per-file `flutter test --no-pub --plain-name 'ML-004'` commands plus the combined four-file ML-004 selector.
- COMPLETE_1/main overlap selectors: contact-picker `GM-036` passed; group-info `GM-036` passed; membership-smoke `GM-036` passed; contact-picker `GE-015` was blocked with exit 79 because no matching test exists in that file, confirmed by `rg -n "GE-015" test/features/groups/presentation/contact_picker_wired_test.dart` returning no matches.
- Whole-file preservation tests passed for all four touched test files.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.
- `./scripts/run_test_gates.sh completeness-check` failed outside ML-004 scope with `Completeness check: 732/733 test files classified` and unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
- `git diff --check` passed.

Skipped duplicate/out-of-scope work:

- Did not update the integration breakdown ledger.
- Did not import source worktree docs or unrelated row coverage.
- Did not touch production files.
- Did not recreate, rewrite, or rerun the original source worktree implementation plan.

QA scrutiny:

- Verify the `GE-015` contact-picker selector absence is an accepted pre-existing/main-overlap condition rather than an ML-004 blocker.
- Verify the completeness-check unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` is unrelated to this ML-004 import and should be handled outside this session.

## QA Review

Verdict: `pass`.

Findings: no blocking findings.

Evidence reviewed:

- Plan contract, execution progress, and executor handoff were read. The contract limits this session to ML-004 import/reconcile in four target test files and says production changes are expected to be none unless exact ML-004 evidence requires them.
- Executor anchor classifications are present and complete: all four source ML-004 anchors are classified as `imported`.
- Source-worktree anchors were compared against current target files. `create_group_with_members_use_case_test.dart` imports the source create proof at line 772; `contact_picker_wired_test.dart` imports the existing-group picker proof at line 1038 with current-main helper adaptation; `group_info_wired_test.dart` imports the UI status proof at line 1026; `group_membership_smoke_test.dart` imports the smoke acceptance proof at line 413.
- The imported tests stay within ML-004 row behavior: mixed B/C/D batch invite where Dave fails, Bob/Charlie succeed, Dave remains failed/resendable or absent from local accepted state, and no failed recipient is silently treated as joined.
- No production change is required by the evidence. The source ML-004 accepted evidence was tests-only, the current ML-004 selectors pass with test-only imports, and unrelated dirty production files were not evaluated as row-owned ML-004 changes.

Verification commands and results:

- `rg -n "ML-004" test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` exited 0. It found the four row-owned selectors at `create_group_with_members_use_case_test.dart:772`, `contact_picker_wired_test.dart:1038`, `group_info_wired_test.dart:1026`, and `group_membership_smoke_test.dart:413`, plus ML-004 test data names at `create_group_with_members_use_case_test.dart:786` and `group_membership_smoke_test.dart:497`.
- `rg -n "GE-015" test/features/groups/presentation/contact_picker_wired_test.dart` exited 1 with no matches.
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-004'` exited 0 with `All tests passed!`.
- `git diff --check` exited 0.

Non-green item classification:

- Contact-picker `GE-015` selector exit 79 is accepted as external/pre-existing, not a row blocker. Independent provenance checks found no `GE-015` selector in `HEAD` for `contact_picker_wired_test.dart`, and the current contact-picker diff only adds the ML-004 selector rather than removing `GE-015`.
- `./scripts/run_test_gates.sh completeness-check` unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` is accepted as external/pre-existing, not a row blocker. The unmatched file is outside the four ML-004 target files and `git status --short -- test/shared/fakes/fake_group_pubsub_network_test.dart` is clean.

Final session status can be `accepted`.

## Final Execution Verdict

Status: `accepted`.

Files touched in this session:

- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-004-plan.md`

Anchor classifications:

- `create_group_with_members_use_case_test.dart` ML-004 create roster/invite-state anchor: `imported`.
- `contact_picker_wired_test.dart` ML-004 existing-group picker-state anchor: `imported`.
- `group_info_wired_test.dart` ML-004 failed-recipient UI-state anchor: `imported`.
- `group_membership_smoke_test.dart` ML-004 delivered-recipient accept/failed-recipient pending anchor: `imported`.

Tests and gates run:

- Duplicate/overlap checks from this plan completed before import.
- Four per-file `flutter test --no-pub --plain-name 'ML-004'` selectors passed.
- Combined four-file `flutter test --no-pub ... --plain-name 'ML-004'` passed in executor and QA.
- `GM-036` overlap selectors for contact picker, group info, and membership smoke passed.
- Contact-picker `GE-015` selector returned exit 79 because no matching selector exists in that file; QA verified it was absent in `HEAD` and not removed by ML-004, so this is external/pre-existing and not a row blocker.
- Whole-file preservation tests passed for all four touched test files.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.
- `./scripts/run_test_gates.sh completeness-check` failed externally with `Completeness check: 732/733 test files classified` and unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`; QA verified that file is outside ML-004 scope and clean in `git status`.
- `git diff --check` passed after executor handoff and after QA plan edits.

Skipped duplicate or out-of-scope work:

- Did not duplicate existing `GM-036` coverage beyond the row-owned ML-004 selectors.
- Did not import source worktree docs, source closure docs, or unrelated rows.
- Did not touch production files for ML-004.
- Did not recreate, rewrite, or rerun the original worktree implementation plan.
- Did not update the integration breakdown ledger; closure/controller verification owns that per current instruction.

Blockers: none for ML-004.
