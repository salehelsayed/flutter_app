# INTEGRATE-ML-006 Worktree-to-Main Integration Plan

Status: accepted
Acceptance status: accepted
Source row: `ML-006 | Remove an offline member and converge after reconnect`
Integration row: `INTEGRATE-ML-006`

## Planning Progress

- 2026-05-17 20:19:34 CEST - Evidence Collector started. Files inspected since last update: target path existence, `git status --short`, source ML-006 plan excerpt search, main integration breakdown search, and main COMPLETE_1 overlap search. Decision/blocker: target plan file was absent; main checkout contains existing unrelated dirty worktree changes that must be preserved. Next action: inspect exact source ML-006 row, source breakdown, source closure evidence, touched files, and main overlap rows GM-005/GM-018/GM-020 before finalizing this integration contract.
- 2026-05-17 20:28:00 CEST - Evidence Collector completed. Files inspected since last update: source matrix row ML-006, source session breakdown ML-006 block, source ML-006 plan final verdict/evidence, main worktree-to-main integration breakdown row mapping, main COMPLETE_1 rows GM-005/GM-018/GM-020, and current main target-file marker searches. Decision/blocker: source ML-006 is accepted historically, but main integration row is still pending; current main has GM-005/GM-018/GM-020 and ML-005/private_online_remove markers, with no ML-006/private_offline_remove markers found in the exact ML-006 target files during planning. Next action: draft a present/partial/missing integration contract.
- 2026-05-17 20:30:00 CEST - Planner completed. Files inspected since last update: this plan draft surface and all source/main evidence above. Decision/blocker: contract is evidence-gated and execution-ready; it must inspect main again before import, preserve dirty work, and import only row-owned ML-006 deltas if missing or partial. Next action: reviewer pass for overlap and scope drift.
- 2026-05-17 20:31:00 CEST - Reviewer completed. Files inspected since last update: final draft sections, pre-application checklist, exact source evidence, source touched files, overlap preservation tests, and scope guard. Decision/blocker: sufficient with no structural blocker; plan explicitly excludes ML-007 and generic GM/later-row imports. Next action: arbiter pass.
- 2026-05-17 20:32:00 CEST - Arbiter completed. Files inspected since last update: reviewer findings, mandatory section coverage, execution tests/gates, known-failure interpretation, and done criteria. Decision/blocker: no structural blocker remains. Next action: hand off to execution for INTEGRATE-ML-006 only.

## Execution Progress

- 2026-05-17 20:28:03 CEST - Role: Controller contract extraction started - Files inspected since last update: execution QA orchestrator skill, `git status --short`, current branch, this INTEGRATE-ML-006 plan, and broad ML-006/private_offline_remove/GM-005/GM-018/GM-020 marker search. Decision/blocker: nested execution will use isolated `codex exec` child agents; main worktree is heavily dirty, including row-owned target files, and must be preserved. Next action: spawn Executor to inspect exact source-vs-main ML-006 anchors, classify present/partial/missing, import only missing row-owned deltas if needed, and run required verification.
- 2026-05-17 20:31:53 CEST - Role: Executor pre-edit inspection completed - Files inspected since last update: `git status --short`, this plan, main/source marker searches for the six allowed Dart surfaces, main integration breakdown, COMPLETE_1 overlap rows, and source ML-006 snippets. Classification: direct test name in `drain_group_offline_inbox_use_case_test.dart` missing in main/source-present; fake-network test name in `group_membership_smoke_test.dart` missing in main/source-present; `private_offline_remove` criteria requirement/map/dispatch and `ml006OfflineRemovalProof` validation missing in main/source-present; `private_offline_remove` criteria tests and helper verdict missing in main/source-present but source has later IR-004 extensions that must be omitted; runner/listing support missing in main/source-present; harness role/proof dispatch missing in main/source-present but source has later IR-004 proof fields that must be omitted. Overlap anchors preserved in main: `GM-005`/`gm005OfflineRemovalProof`, `GM-018`/`gm018RemainingDeliveryContinuityProof`, and `GM-020`/`gm020ImmediateRecipientExclusionProof` remain present. Decision/blocker: ML-006 is missing, not already equivalent; import only ML-006-owned deltas and preserve all unrelated dirty worktree edits. Next action: patch only allowed ML-006 surfaces plus this plan.
- 2026-05-17 20:49:00 CEST - Role: Executor import completed - Files changed by this row: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and this plan. Imported anchors now present: ML-006 direct drain replay test, ML-006 fake-network membership smoke test, `private_offline_remove` criteria/listing/runner support, `ml006OfflineRemovalProof` validation, criteria acceptance/rejection tests, and harness role/proof dispatch. Preserved overlap anchors: GM-005, GM-018, and GM-020 selectors/proofs remain present and were not renamed or duplicated. Production files touched by Executor: none. Omitted adjacent scope: ML-007, generic GM-005 import work, and later IR-004/private_offline_remove proof extensions.
- 2026-05-17 20:49:00 CEST - Role: Executor verification completed - Accepted results: `dart format` on the six touched Dart files (`0 changed`); `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-006'` passed (`+1`); `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-006'` passed (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_offline_remove'` passed (`+7`); GM-005 smoke selector passed (`+1`); GM-005 criteria selector passed (`+7`); GM-018 smoke selector passed (`+1`); GM-018 criteria selector passed (`+4`); GM-020 smoke selector passed (`+1`); GM-020 criteria selector passed (`+5`); `dart analyze` on the six touched Dart files passed (`No issues found!`); `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios` passed and listed `private_offline_remove`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+173: All tests passed!`); `git diff --check` passed. `./scripts/run_test_gates.sh completeness-check` failed only on the known unrelated classification gap: `Completeness check: 732/733 test files classified` with unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`; no ML-006 touched file was implicated.
- 2026-05-17 20:49:00 CEST - Role: Executor live proof completed - Exact historical source UUID command could not start because Alice device `560D3E2D-78F8-4D28-A010-16B399581C99` was unavailable in current `flutter devices`; current available iOS 26.2 devices were then used. Live command with Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` passed for run `1779043375583`: `private_offline_remove proof passed: private_offline_remove verdicts valid for alice, bob, charlie`. Logs/verdicts were written under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_remove_1x9YpD`. Decision/blocker: no Executor blocker remains; QA can proceed.
- 2026-05-17 20:52:40 CEST - Role: QA Reviewer completed - Files inspected since last update: this plan, Executor final summary, `git status --short`, row-owned `git diff --name-only`, row-owned marker searches, no-ML-007/no-IR-004 marker search, `git diff --check`, and live verdict files under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_remove_1x9YpD`. Decision/blocker: accepted; no QA blocker found. Current worktree has unrelated dirty production and test files, but the ML-006 row-owned changed paths recorded by Executor are limited to the six allowed Dart surfaces plus this plan. Next action: keep INTEGRATE-ML-006 closed; the next safe pipeline action is a separate ML-007 planning/execution pass, not part of this row.

## Final Execution Verdict

Verdict: accepted

QA accepted INTEGRATE-ML-006 after reviewing the plan, Executor final summary, row-owned diff/status, row-owned marker searches, diff hygiene, and the live verdict files. The Executor recorded a pre-application classification before import: ML-006 direct test, smoke test, `private_offline_remove` criteria/listing/runner support, `ml006OfflineRemovalProof` validation, criteria tests, and harness role/proof dispatch were missing in main and source-present. The same entry recorded GM-005, GM-018, and GM-020 overlap anchors already present before ML-006 import.

Changed paths accepted for this row:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-006-plan.md`

Tests and gates accepted from Executor evidence:

- `dart format` on the six touched Dart files: passed, `0 changed`.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-006'`: passed, `+1`.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-006'`: passed, `+1`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_offline_remove'`: passed, `+7`.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues'`: passed, `+1`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-005'`: passed, `+7`.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-018'`: passed, `+1`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-018'`: passed, `+4`.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-020'`: passed, `+1`.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-020'`: passed, `+5`.
- `dart analyze` on the six touched Dart files: passed, `No issues found!`.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios`: passed and listed `private_offline_remove`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`: passed, `+173: All tests passed!`.
- `./scripts/run_test_gates.sh completeness-check`: failed only on the accepted unrelated classification gap, `Completeness check: 732/733 test files classified`, unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`; no ML-006 touched file was implicated.
- `git diff --check`: passed in Executor evidence and passed again during QA confirmation.
- Live `private_offline_remove` proof: passed for run `1779043375583` with Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict file reports `private_offline_remove verdicts valid for alice, bob, charlie`.

Overlap preservation evidence:

- Row-owned marker search confirms `private_offline_remove`, `ML-006`, and `ml006OfflineRemovalProof` are present in the direct test, smoke test, criteria, criteria tests, runner, and harness.
- Row-owned marker search confirms GM-005, GM-018, and GM-020 selectors/proofs remain present, including `gm005OfflineRemovalProof`, `gm018RemainingDeliveryContinuityProof`, and `gm020ImmediateRecipientExclusionProof`.
- Row-owned no-adjacent-scope search found no `ML-007`, `ml007`, `IR-004`, `ir004`, or `ir004PostRemovalReplayProof` markers.
- Current `git diff` against HEAD includes pre-existing GM-005 additions in shared row-owned files, but the Executor pre-edit classification recorded GM-005 overlap anchors present before ML-006 import; QA treats them as preserved overlap, not ML-006 imported scope.

Production files touched by this row: none. The current worktree contains unrelated dirty production files under `lib/`, `go-mknoon/`, `pubspec.yaml`, and `info.plist`; QA did not modify them and does not attribute them to INTEGRATE-ML-006.

Skipped or omitted adjacent scope: ML-007, generic GM-005 implementation/import work, GM-018/GM-020 implementation work beyond preservation checks, IR-004/later `private_offline_remove` proof extensions, source matrix docs, COMPLETE_1 docs, and the worktree-to-main integration breakdown ledger.

Blockers: none.

Next safe action: stop this row as accepted. A later ML-007 row may start only as a separate integration pass.

## real scope

This is one worktree-to-main integration row for source row `ML-006` only. It is not the original ML-006 implementation rollout, not gap-closure, and not a rerun of the source worktree plan.

The execution job is to compare the source ML-006 row evidence against current main and decide whether the ML-006 row-owned changes are already present, partially present, or missing. If missing or partial, it may import only meaningful ML-006 deltas:

- the direct ML-006 replay/drain test in `drain_group_offline_inbox_use_case_test.dart`;
- the ML-006 fake-network membership smoke selector in `group_membership_smoke_test.dart`;
- `private_offline_remove` criteria, runner, and harness support;
- `ml006OfflineRemovalProof` validation and rejection tests;
- minimal integration docs for the current integration row.

Production files are expected to stay untouched. A production edit is allowed only if a focused ML-006 test proves main has a real row-owned behavior gap after the row-owned tests/harness support are present.

Out of scope: `ML-007` and later source rows, generic `gm005` import work, GM-018/GM-020 implementation, IR-004 or later `private_offline_remove` proof extensions, re-add, rapid ordering, duplicate/stale remove, churn, media, notification, key-epoch, observability, stress, and broad lifecycle scopes.

## closure bar

This plan is reusable when it gives execution enough evidence to integrate ML-006 without duplicating existing COMPLETE_1 coverage. It is execution-ready when it names exact source evidence, exact source touched files, pre-application checks, allowed deltas, overlap preservation tests, known failure interpretation, and stop rules.

Integration is complete only in a later execution pass if:

- current main is inspected and classified as already-present, partial, or missing for each ML-006 row-owned delta;
- any imported delta is limited to the ML-006 files and proof fields listed here;
- no GM-005/GM-018/GM-020 coverage is duplicated or weakened;
- production files stay untouched unless focused ML-006 tests prove otherwise;
- focused ML-006 selectors, `private_offline_remove` criteria, overlap preservation selectors, groups gate, completeness-check, and diff hygiene produce accepted evidence;
- live `private_offline_remove` proof is rerun if harness changes are imported, unless execution records a defensible main-equivalence reason to rely on source evidence without rerun.

This planning artifact itself is not acceptance evidence for the row.

## source of truth

Authoritative inputs for this integration row:

1. Current main checkout code and tests at execution time. This wins for present/partial/missing classification.
2. Main integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source row `ML-006` in `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`.
4. Source breakdown block `Session ML-006` in `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`.
5. Source ML-006 closure plan `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md`.
6. Main COMPLETE_1 overlap rows `GM-005`, `GM-018`, and `GM-020` in `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
7. `Test-Flight-Improv/test-gate-definitions.md` and `./scripts/run_test_gates.sh` for named gates.

Do not treat the source worktree's current dirty diff as a clean patch source. Reuse the source row, breakdown, plan, and closure evidence as historical source-of-truth, then import only row-owned meaningful deltas that are still absent or partial in main.

## session classification

`evidence-gated`

The plan is execution-ready, but execution must first inspect main and classify the ML-006 deltas as already present, partial, or missing. If already present and equivalent, execution should record equivalence and avoid importing duplicate tests or harness support. If partial or missing, execution may import only the row-owned ML-006 deltas named in this plan.

## exact problem statement

Source ML-006 proves that Charlie is offline when Alice removes Charlie from a private A/B/C group; Alice and Bob send post-removal messages; Charlie reconnects and drains replay; Charlie converges to removed state, cannot decrypt or display A/B post-removal messages, does not retain the rotated epoch, and cannot publish after removal.

Main already has overlapping COMPLETE_1 coverage:

- `GM-005`: generic remove-C-while-C-offline proof with GM-specific `gm005OfflineRemovalProof`.
- `GM-018`: remaining-member delivery continues under stale removed-member pressure.
- `GM-020`: removed member is excluded from post-removal durable recipient lists.

The integration risk is importing ML-006 by copying generic GM-005 or adjacent/later source-worktree scopes instead of only the ML-006 private-matrix proof. The execution pass must add or preserve the row-named `ML-006` and `private_offline_remove` contract without duplicating GM-005/GM-018/GM-020 coverage or weakening their existing proofs.

Planning-time main marker search found GM-005/GM-018/GM-020 and ML-005/private_online_remove support in the target files, while no `ML-006`, `private_offline_remove`, or `ml006OfflineRemovalProof` marker was found in the exact target code/harness files. Execution must rerun that inspection before editing because the main checkout is dirty and may change.

## exact source evidence

Source ML-006 final status is `accepted` / `Covered` historically, not automatically accepted for main.

Exact source evidence recorded for ML-006:

- Source matrix row `ML-006` says Covered on 2026-05-11 by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md`.
- Direct selector: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-006'` passed with `+1`.
- Direct test name: `ML-006 removed offline member drains removal before post-removal replay and stores no post-removal plaintext`.
- Fake-network selector: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-006'` passed with `+1`.
- Fake-network test name: `ML-006 offline removed member converges removed after reconnect and cannot read A/B post-removal messages`.
- Criteria selector: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_offline_remove'` passed with `+7`.
- Criteria/harness proof: `private_offline_remove` emits and validates `ml006OfflineRemovalProof`, rejecting missing proof, Charlie plaintext leak, accepted Charlie send, missing A/B delivery, missing stale reconnect/drain, and Charlie retaining the rotated epoch.
- Required gate: `./scripts/run_test_gates.sh groups` passed with `+132`.
- Required gate: `./scripts/run_test_gates.sh completeness-check` passed with `732/732`.
- Hygiene: `git diff --check` passed with no output.
- Accepted live proof: exact-relay `private_offline_remove` run id `1778531722491`, path `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_remove_r1v8cx`.
- Accepted live app peers: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`, all verified as iOS 26.2 CoreSimulator devices.
- Live verdict details: A/B epoch `2`, member lists excluding Charlie, Alice/Bob post-removal message exchange, Charlie stale pre-removal state before reconnect, Charlie drain to removed state, no Charlie group after catch-up, no rotated epoch retained by Charlie, `postRemovalPlaintextCount=0`, Charlie post-removal publish rejected as `groupNotFound`, and no Alice/Bob post-removal receipt on Charlie.
- Rejected live attempts: `1778530720085`, `1778531193186`, and `1778531530142` were unusable due to overlapping `gm033` device-lane contention.
- Production files stayed untouched in source ML-006 closure.
- Generic `gm005` and `gm033` evidence was explicitly not used for ML-006 closure.

## exact source touched files

Source ML-006 changed these code/test/harness files:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Source ML-006 closure also updated these source docs:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md`

For main integration, do not import the source docs wholesale. Minimal docs mean this plan plus any later integration-row ledger/closure update required by the worktree-to-main process.

## overlap comparison

Main COMPLETE_1 overlap rows:

- `GM-005` owns generic offline removal: remove C while C is offline, C catches up removed, cannot access post-removal content, and A/B delivery continues. It uses `gm005OfflineRemovalProof`, exact `--scenario gm005`, and already records no product behavior changes required. ML-006 must not rename or duplicate GM-005 as closure.
- `GM-018` owns remaining-member delivery under stale removed-member pressure. It has application/member-removal proof, membership smoke proof, Go stale-pressure proof, criteria/runner/harness support, and exact `--scenario gm018`. ML-006 must not import GM-018 direct tests, Go tests, or stale-pressure delivery logic.
- `GM-020` owns immediate removed-recipient exclusion for durable payloads. It has send/member-removal/membership smoke/criteria/runner/harness proof and exact `--scenario gm020`. ML-006 must not import GM-020 recipient-proof tests or harness fields.

ML-006 may share the accepted three-role offline-removal harness shape, but it must remain distinct through:

- scenario name `private_offline_remove`;
- proof field `ml006OfflineRemovalProof`;
- row id `ML-006`;
- row-named direct selector;
- row-named fake-network selector;
- criteria rejections specific to ML-006.

Do not import later source-worktree additions that also extend `private_offline_remove`, such as IR-004 `ir004PostRemovalReplayProof` or any other adjacent proof field.

## pre-application inspection checklist

Before any import, execution must inspect the exact files below in current main and record whether each ML-006 delta is already present, partial, or missing.

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Search for `ML-006 removed offline member drains removal before post-removal replay and stores no post-removal plaintext`.
  - Check whether it proves replayed self-removal before same-page/later-page A/B post-removal replay can persist or decrypt, local group/key deletion, `group:leave`, and no later cursor paging after removal.
  - Preserve unrelated dirty edits and existing non-ML-006 replay tests.

- `test/features/groups/integration/group_membership_smoke_test.dart`
  - Search for `ML-006 offline removed member converges removed after reconnect and cannot read A/B post-removal messages`.
  - Check existing `GM-005`, `GM-018`, and `GM-020` selectors before inserting anything.
  - Import no generic `gm005` duplication and no GM-018/GM-020 scopes.

- `integration_test/scripts/group_multi_party_device_criteria.dart`
  - Search for `private_offline_remove` requirement, scenario map entry, criteria switch/dispatcher entry, `ml006OfflineRemovalProof`, and row-id check `ML-006`.
  - Preserve existing `gm005OfflineRemovalProof`, `gm018RemainingDeliveryContinuityProof`, and `gm020ImmediateRecipientExclusionProof` behavior.
  - Do not import IR-004/later `private_offline_remove` proof extensions.

- `test/integration/group_multi_party_device_criteria_test.dart`
  - Search for `private_offline_remove`, `ml006OfflineRemovalProof`, valid verdict coverage, and rejection tests for missing ML-006 proof, Charlie plaintext leak, accepted Charlie send, missing A/B delivery, missing stale reconnect/drain, and Charlie retaining rotated epoch.
  - Preserve existing GM-005/GM-018/GM-020 criteria tests.

- `integration_test/scripts/run_group_multi_party_device_real.dart`
  - Search for `private_offline_remove` in scenario listing, role/scenario validation, usage text, and any GM-005-shared allowlist branch.
  - Do not import source-worktree scenario-list additions for later rows.

- `integration_test/group_multi_party_device_real_harness.dart`
  - Search for `_rolesByScenario` or equivalent role map entry for `private_offline_remove`.
  - Search for any scenario dispatch that maps `private_offline_remove` onto the offline-removal flow.
  - Search for `isMl006`, `ML-006 Private Group`, `ML-006 Alice after offline Charlie removal`, `ML-006 Bob after offline Charlie removal`, `ML-006 Charlie after offline removal`, and `ml006OfflineRemovalProof` in Alice/Bob/Charlie verdicts.
  - Preserve GM-005/GM-018/GM-020 harness branches and any ML-005/private_online_remove support already in main.

- Integration docs
  - Inspect this plan and the main integration breakdown before execution.
  - Do not update source worktree docs, main source matrix docs, or COMPLETE_1 docs for this planning row.

## files and repos to inspect next

Main checkout files to inspect before execution:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Source historical files to use only as evidence:

- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md`

## existing tests covering this area

Main overlap already covers adjacent behavior through:

- `GM-005` smoke/criteria/harness/live proof for generic offline C removal.
- `GM-018` app/smoke/Go/criteria/harness/live proof for remaining-member delivery under stale pressure.
- `GM-020` send/app/smoke/criteria/harness/live proof for immediate durable recipient exclusion.

Planning-time search of current main target files found:

- existing `gm005`, `GM-005`, `gm005OfflineRemovalProof`;
- existing `GM-018`, `gm018RemainingDeliveryContinuityProof`;
- existing `GM-020`, `gm020ImmediateRecipientExclusionProof`;
- existing `ML-005`, `private_online_remove`, `ml005OnlineRemovalProof`;
- no target-file `ML-006`, `private_offline_remove`, or `ml006OfflineRemovalProof` markers.

Execution must repeat this check because the main checkout is dirty.

## regression/tests to add first

Do not add a production fix first. If ML-006 is missing or partial, import the row-owned tests/proof support first:

1. Direct selector in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`:
   `ML-006 removed offline member drains removal before post-removal replay and stores no post-removal plaintext`.

2. Fake-network selector in `test/features/groups/integration/group_membership_smoke_test.dart`:
   `ML-006 offline removed member converges removed after reconnect and cannot read A/B post-removal messages`.

3. `private_offline_remove` scenario support in:
   `integration_test/scripts/group_multi_party_device_criteria.dart`,
   `test/integration/group_multi_party_device_criteria_test.dart`,
   `integration_test/scripts/run_group_multi_party_device_real.dart`,
   and `integration_test/group_multi_party_device_real_harness.dart`.

4. Criteria tests proving the valid ML-006 verdict and rejecting weak evidence:
   missing `ml006OfflineRemovalProof`, Charlie plaintext leak, accepted Charlie send, missing A/B delivery, missing stale reconnect/drain, and Charlie retaining the rotated epoch.

If these tests pass on existing main production code, do not edit production files.

## step-by-step implementation plan

1. Record `git status --short` and preserve all unrelated dirty worktree changes.
2. Rerun the exact pre-application inspection checklist above.
3. Classify each ML-006 delta as already present, partial, or missing.
4. If all row-owned ML-006 deltas are already present and equivalent, do not import duplicate code. Record equivalence and run the focused ML-006 and overlap tests listed below.
5. If partial or missing, import only the row-owned direct test, fake-network test, `private_offline_remove` criteria/runner/harness support, criteria tests, and minimal integration docs.
6. While importing, use source ML-006 evidence as a guide rather than applying broad source-worktree patches. Avoid source-worktree scenario-list churn for later rows.
7. Preserve COMPLETE_1 GM-005/GM-018/GM-020 behavior. Do not rename their proof fields, expected errors, selectors, or scenario names.
8. Run focused ML-006 selectors and `private_offline_remove` criteria selector.
9. Run affected GM-005/GM-018/GM-020 overlap preservation selectors because ML-006 touches shared smoke/criteria/runner/harness files.
10. Run `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`.
11. If harness/runner/criteria files were imported or changed, prefer rerunning live exact-relay `private_offline_remove`. If execution skips live rerun, it must justify source evidence plus main equivalence, with no harness changes and no changed live proof semantics.
12. Stop at INTEGRATE-ML-006. Do not continue to ML-007.

## risks and edge cases

- Main may already contain partial ML-006 work from another dirty change. Execution must preserve it and reconcile rather than overwrite.
- Shared criteria/harness files also own GM-005/GM-018/GM-020. A small import can accidentally alter existing scenarios.
- Source `private_offline_remove` was later extended by adjacent rows such as IR-004. Importing a broad source chunk could accidentally pull later row proof fields.
- Live device proof can be contaminated by same-device scenario contention. Source rejected three overlapping attempts before accepted run `1778531722491`; execution should use a clean process-lane check if it reruns live proof.
- Completeness-check may expose an unrelated existing fake classification gap from current main. Classify only exact pre-existing/unrelated failures; do not hide ML-006/touched-file classification gaps.

## exact tests and gates to run

Focused ML-006 selectors:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'ML-006'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-006'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_offline_remove'
```

Affected COMPLETE_1 overlap preservation selectors:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-005'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-018'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-018'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-020'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-020'
```

Conditional overlap selectors if execution touches their direct owner files:

```bash
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-018'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-020'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-020'
```

Conditional Go preservation only if Go files are touched, which is not expected:

```bash
(cd go-mknoon && go test ./node -run '^TestGM018RemainingMembersDeliverySurvivesRemovedMemberStalePressure$' -count=1)
```

Named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Live proof, required if harness/runner/criteria semantics are imported or changed; otherwise skip only with a written main-equivalence justification:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_offline_remove -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245
```

## known-failure interpretation

- Any focused ML-006 selector failure is owned by this integration until triaged as behavior, import conflict, test-shape issue, harness issue, environment, or unrelated pre-existing failure.
- Any GM-005/GM-018/GM-020 focused preservation failure after touching shared files is a blocker unless proven pre-existing and unrelated.
- `./scripts/run_test_gates.sh completeness-check` may fail on an unrelated existing fake classification gap, previously recorded in this integration pipeline as `test/shared/fakes/fake_group_pubsub_network_test.dart` with `732/733`. If present, record exact output and classify it as unrelated/pre-existing only if no ML-006 touched file or newly imported file is unclassified.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` must be treated as required. If it fails outside touched ML-006/overlap scope, record the exact failing tests and decide whether they are unrelated existing failures before closing.
- `git diff --check` must pass for the whole dirty diff or any failure must be clearly unrelated pre-existing whitespace. Prefer fixing only whitespace introduced by this row.
- Do not claim live proof from source if main harness/runner/criteria semantics changed during integration. Prefer rerun.

## done criteria

- This plan remains the only file created by the planning pass.
- Execution has classified ML-006 deltas in main as already present, partial, or missing.
- Missing/partial imports, if any, are limited to row-owned ML-006 tests, fake-network proof, `private_offline_remove` criteria/runner/harness support, criteria tests, and minimal integration docs.
- No production file is changed unless focused ML-006 tests prove a behavior gap.
- No GM-005/GM-018/GM-020 coverage is duplicated, renamed, or weakened.
- Focused ML-006 selectors and criteria selector have accepted results.
- Affected GM-005/GM-018/GM-020 preservation selectors have accepted results.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` have accepted results or exact accepted unrelated known-failure classification.
- Live `private_offline_remove` proof is rerun if harness changes are imported, or execution records a defensible no-rerun equivalence justification.
- Integration stops at INTEGRATE-ML-006 and does not move to ML-007.

## scope guard

Do not modify or import:

- `ML-007` or any later ML rows;
- generic GM-005 implementation or proof as a substitute for ML-006;
- GM-018 stale-pressure delivery code/tests beyond preservation checks;
- GM-020 recipient exclusion code/tests beyond preservation checks;
- IR-004/later `private_offline_remove` extensions;
- production group, bridge, Go, relay, database, UI, notification, media, or key-management files unless ML-006 focused tests prove a row-owned production gap.

Do not rewrite source matrix, COMPLETE_1 matrix, source worktree docs, or original source ML-006 plan during this planning row.

## accepted differences / intentionally out of scope

- Main COMPLETE_1 can keep `gm005OfflineRemovalProof`; ML-006 requires `ml006OfflineRemovalProof` and must not collapse the two.
- Source ML-006 closure used exact iOS 26.2 app-peer proof from May 11, 2026. Main integration may rely on it only if execution proves main equivalence and did not change harness/runner/criteria semantics; otherwise live proof should be rerun.
- Source later rows may also use `private_offline_remove`; those later proof fields are intentionally out of scope.
- Existing unrelated dirty worktree changes are preserved and not normalized by this row.

## dependency impact

INTEGRATE-ML-006 depends on accepted INTEGRATE-ML-005 as an online-removal baseline and on existing COMPLETE_1 GM-005/GM-018/GM-020 coverage remaining intact. Completing this row prepares the pipeline for INTEGRATE-ML-007, but this plan does not authorize moving to ML-007.

If execution blocks on conflicts or live-device fixture contention, record the blocker for INTEGRATE-ML-006 and stop. Do not skip ahead.

## reviewer findings

- Sufficiency: sufficient as-is for an execution pass.
- Missing files/tests/gates: none structurally missing. The plan includes exact target files, focused ML-006 selectors, overlap preservation selectors, gates, diff hygiene, and live-proof policy.
- Stale assumptions: planning-time marker searches can become stale because the main checkout is dirty. Execution must rerun them before editing.
- Overengineering: the allowed import set is deliberately narrow; production changes are conditional only.
- Minimum needed: inspect present/partial/missing, import only row-owned missing deltas, run focused tests/gates, record evidence or blocker, and stop at ML-006.

## arbiter decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact line-by-line patch selection belongs to execution after current-main inspection.
- Accepted differences: source ML-006 is historically accepted, but this main integration row is only execution-ready; acceptance requires a later execution result.
- Final arbiter verdict: execution-ready for INTEGRATE-ML-006 only.
