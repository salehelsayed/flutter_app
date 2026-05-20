Status: accepted
Acceptance Status: accepted

# INTEGRATE-ML-007 Worktree-to-Main Integration Plan

## Planning Progress

- 2026-05-17T21:00:30+02:00 - Evidence Collector completed. Files inspected since last update: source ML-007 matrix row, source breakdown Session ML-007 block, source ML-007 plan/evidence, main integration breakdown ML-007 mapping, COMPLETE_1 GM-006/GM-007/GM-008/GM-019/GM-021/GM-024 overlap rows, and current main marker scans. Decision/blocker: source ML-007 was tests/harness-only with production untouched; current main marker scan found no `ML-007`, `private_readd_current`, or `ml007ReaddCurrentProof` anchors in the six source-touched files, but execution must still classify present/partial/missing by file before importing. Next action: write the minimal integration contract.
- 2026-05-17T21:00:30+02:00 - Planner completed. Files inspected since last update: source touched-file list, source proof commands, source live proof, COMPLETE_1 overlap touched files and selectors. Decision/blocker: allow only missing row-owned ML-007 deltas and overlap preservation checks; do not import generic GM coverage or adjacent re-add/churn/history/key/media work. Next action: reviewer pass.
- 2026-05-17T21:00:30+02:00 - Reviewer completed. Files inspected since last update: complete draft contract, scope guard, focused test list, overlap selector list, and known-failure rule. Decision/blocker: sufficient for execution if the executor performs exact pre-application inspection before any source import. Next action: arbiter pass.
- 2026-05-17T21:00:30+02:00 - Arbiter completed. Files inspected since last update: reviewer findings and closure bar. Decision/blocker: no structural blockers remain; this plan is execution-ready for INTEGRATE-ML-007 only, not accepted. Next action: execute in a later pass without moving to ML-008.

## real scope

Process exactly `INTEGRATE-ML-007` for source row `ML-007 | Re-add a previously removed member with current membership and key state`.

This is a worktree-to-main integration contract, not a fresh implementation rollout and not gap-closure. Reuse the source worktree row, source breakdown entry, source ML-007 plan, and source closure evidence as historical source of truth. Do not recreate, rewrite, or rerun the original worktree ML-007 implementation plan.

Allowed execution deltas are only row-owned, meaningful ML-007 deltas if main is missing or partially missing them:

- direct/app-side ML-007 test;
- fake-network/private-matrix ML-007 smoke test;
- `private_readd_current` criteria, runner, and harness support;
- `ml007ReaddCurrentProof`;
- `private_readd_current` criteria accept/reject tests;
- minimal integration docs.

Production files are expected to stay untouched. Inspect production only if focused ML-007 tests prove a real row-owned behavior gap after the test/harness import.

## closure bar

This plan is complete when an executor can safely decide one of these outcomes for ML-007 only:

- `skipped_already_present`: all meaningful ML-007 anchors are already present in main and the focused/source plus overlap preservation selectors pass or have accepted unrelated known-failure classification.
- `accepted`: missing or partial row-owned ML-007 deltas were integrated, focused/source plus overlap preservation selectors pass or have accepted unrelated known-failure classification, production files stayed untouched unless a focused ML-007 regression proved otherwise, and the main integration ledger can be updated for INTEGRATE-ML-007 only.
- `blocked_conflict` or `blocked_external_fixture`: exact blockers are recorded without moving to ML-008.

This plan itself is not accepted evidence. Its status is `execution-ready`.

## source of truth

Authoritative sources for execution, in order:

1. Current main checkout code and tests, including existing dirty changes. Do not revert or overwrite unrelated edits.
2. Main integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`.
4. Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`.
5. Source ML-007 plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md`.
6. Main COMPLETE_1 overlap breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

COMPLETE_1 overlap rows own their own main coverage. They are preservation constraints, not source import targets for ML-007.

## session classification

`implementation-ready` integration contract.

The execution status must start as `execution-ready`, not `accepted`. It can become accepted only after a later executor performs the pre-application inspection, applies any missing/partial ML-007 deltas, and runs the required proof.

## exact problem statement

Source ML-007 already proved a removed Charlie can be re-added to the private group with current membership/config/key state, receive Alice and Bob post-readd messages, publish after re-add, and avoid removed-window plaintext or stale epoch/config. Main has earlier COMPLETE_1 coverage for adjacent re-add shapes, but INTEGRATE-ML-007 is still pending in the main integration breakdown.

Risk during integration: blindly importing source ML-007 could duplicate COMPLETE_1 GM coverage, alias generic `gm006` proof as ML-007, overwrite dirty main work, or accidentally pull later adjacent scopes. Execution must first determine whether ML-007 changes are already present in main, partially present, or missing.

## source ML-007 evidence

Source row exact contract:

| row | scenario | precondition | actions | expected |
|---|---|---|---|---|
| `ML-007` | Re-add a previously removed member with current membership and key state | C was removed earlier. | 1. A re-adds C. 2. C joins with the current config/key. 3. A and B send messages. | C becomes active again and receives new incoming messages. C does not remain stuck on the old epoch or old config. |

Exact historical evidence from the source row and source plan:

- Covered on 2026-05-11 by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md`.
- `group_real_crypto_onboarding_test.dart` added `ML-007 re-add uses current group config and key while retained old key cannot decrypt`.
- `group_membership_smoke_test.dart` added `ML-007 removed member rejoins with current state and receives only post-readd messages`.
- `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_real_harness.dart`, and `run_group_multi_party_device_real.dart` require/emit `private_readd_current` `ml007ReaddCurrentProof` fields and reject missing proof, Charlie removed-window plaintext, stale Charlie epoch/config after re-add, and missing Bob delivery to Charlie.
- Required source evidence passed: direct selector (`+1`), fake-network selector (`+1`), criteria selector (`+5`), `./scripts/run_test_gates.sh groups` (`+132`), `completeness-check` (`732/732`), exact-relay live `private_readd_current` run `1778533168462`, and `git diff --check`.
- Source live proof path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_4vpDKG`.
- Source live app peers: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.
- Source live verdicts recorded final epoch `2` for all roles, member lists including Charlie, Alice and Bob accepted post-readd sends, Charlie receipt of both Alice/Bob post-readd messages, Charlie `removedWindowPlaintextCount=0`, `hasStaleEpochAfterReadd=false`, and Charlie post-readd publish accepted.
- Source production files stayed untouched.

Exact source ML-007 implementation/proof touched files:

- `integration_test/group_real_crypto_onboarding_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Historical source closure docs updated after proof:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md`

## COMPLETE_1 overlap comparison

| COMPLETE_1 row | overlap with ML-007 | execution rule |
|---|---|---|
| `GM-006` | Immediate remove/re-add with current epoch, shared smoke/criteria/runner/harness surfaces. | Preserve existing GM-006 coverage. Do not import or rename generic `gm006ImmediateReaddProof` as ML-007. |
| `GM-007` | Removed-window history boundary around re-add, shared smoke/criteria/runner/harness surfaces. | Preserve M0/M1..M3/M4 history-boundary proof. Do not import history-policy scope as ML-007. |
| `GM-008` | Re-add after restart with persisted epoch, shared smoke/criteria/runner/harness surfaces. | Preserve restart/current-persisted-epoch proof. Do not import restart mechanics as ML-007. |
| `GM-019` | Durable inbox recipient windows before and after re-add, shared smoke/criteria/runner/harness surfaces. | Preserve recipient-window proof. Do not import `send_group_message_use_case.dart` cutoff work unless a focused ML-007 test proves a new ML-007 gap. |
| `GM-021` | Fresh re-add invite/key-package binding and stale package rejection. | Preserve key-package proof. Do not import `send_group_message_use_case.dart`, `go_bridge_client.dart`, or Go validator work as ML-007 unless focused ML-007 tests prove it. |
| `GM-024` | Member display/state convergence for re-added C, shared `group_membership_smoke_test.dart` surface. | Preserve display/topic/member-state convergence. Do not import authoritative snapshot `joinedAt` production work as ML-007. |

The main integration breakdown already maps `ML-007` to `GM-006`, `GM-007`, `GM-008`, `GM-019`, `GM-021`, and `GM-024` as high-risk overlap rows. Current marker scan in main found no `ML-007`, `private_readd_current`, or `ml007ReaddCurrentProof` anchors in the source-touched files, but execution must still perform the file-by-file checklist below before importing.

## files and repos to inspect next

Pre-application inspection must compare source and main for these exact files before any import:

- `integration_test/group_real_crypto_onboarding_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Inspect these production owner files only if focused ML-007 tests fail after the test/harness import:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_members_db_helpers.dart`

## pre-application inspection checklist

Before applying any source hunk, execution must:

1. Run `git status --short` and record existing dirty files. Do not revert unrelated dirty work.
2. For each exact source-touched file, inspect local main changes with `git diff -- <file>` and preserve user/controller edits.
3. Search each main file for `ML-007`, `private_readd_current`, `ml007ReaddCurrentProof`, `ReaddCurrent`, and the two source test names.
4. Search each source file for the same anchors and identify the exact source hunks.
5. Classify each file as `already_present`, `partial`, or `missing`.
6. If all anchors are already present, skip importing and run focused proof only.
7. If partial, import only missing ML-007-specific anchors and reconcile with existing main helpers.
8. If missing, import only row-owned meaningful ML-007 hunks from the six source files.
9. Do not import generic `gm006` code as ML-007.
10. Do not import ML-008, ML-009, ML-011, repeated cycles, rapid ordering, duplicate/stale removal, churn, history policy, key-package, notification, media, or broader key-management scopes.
11. Do not update source worktree docs or COMPLETE_1 docs during this integration row.

## existing tests covering this area

Main COMPLETE_1 already covers adjacent re-add behavior:

- `GM-006` immediate remove/re-add current epoch.
- `GM-007` removed-window history boundary.
- `GM-008` re-add after restart/persisted epoch.
- `GM-019` durable recipient windows around re-add.
- `GM-021` fresh re-add key package binding.
- `GM-024` display/member/topic state convergence after re-add.

These are preservation coverage only. They do not replace ML-007's row-owned `private_readd_current` proof.

## regression/tests to add first

Add nothing from scratch until the pre-application checklist classifies the ML-007 deltas. If missing or partial, import only these source-owned regressions/proof surfaces:

- direct/app-side selector named `ML-007 re-add uses current group config and key while retained old key cannot decrypt`;
- fake-network/private-matrix selector named `ML-007 removed member rejoins with current state and receives only post-readd messages`;
- `private_readd_current` scenario support in criteria, runner, and harness;
- `ml007ReaddCurrentProof` emitted for Alice/Bob/Charlie with `rowId: ML-007`;
- criteria tests that accept valid proof and reject missing proof, Charlie removed-window plaintext, stale epoch/config after re-add, and missing Bob delivery to Charlie.

## step-by-step implementation plan

1. Perform the pre-application inspection checklist.
2. Classify the row as already present, partial, or missing.
3. If already present, do not import. Run the focused ML-007 commands and overlap preservation selectors.
4. If partial, import only the missing ML-007 anchors from the six source-touched files.
5. If missing, import only the row-owned ML-007 hunks from the six source-touched files.
6. Keep production files untouched unless the focused ML-007 direct/smoke/criteria tests expose a real ML-007 behavior gap that cannot be fixed in test/harness code.
7. Run focused ML-007 commands.
8. Run affected COMPLETE_1 overlap preservation selectors based on touched shared files.
9. If criteria/runner/harness support was imported or changed, run the live `private_readd_current` proof.
10. Run named gates and hygiene.
11. Update only minimal main integration docs for INTEGRATE-ML-007 after proof. Do not move to ML-008 in this row.

## risks and edge cases

- Main already has substantial dirty work; source hunks must not overwrite unrelated edits.
- COMPLETE_1 rows already own adjacent coverage; duplicated helper/proof fields can weaken future maintenance.
- `private_readd_current` is shared by later source rows in the worktree; import only ML-007-specific proof requirements, not later quote/media/reaction/churn/history/key extensions.
- Charlie's old key/config state must remain unable to decrypt removed-window traffic after re-add.
- Alice/Bob post-readd delivery to Charlie is required; source ML-007 specifically added Bob post-readd delivery.

## exact tests and gates to run

Focused ML-007 source commands:

```bash
flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-007'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
```

Affected COMPLETE_1 preservation selectors:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-019'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-021'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-006'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-007'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-008'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-019'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-021'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-024'
```

Required named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Required live proof if `private_readd_current` criteria/runner/harness support is imported or changed:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 560D3E2D-78F8-4D28-A010-16B399581C99,511B36DA-7113-41A7-A718-4450C87C0E62,DE36DBBE-64FC-4652-AAD9-17329A1BA245
```

## known-failure interpretation

- If `./scripts/run_test_gates.sh completeness-check` reports only the unrelated existing fake classification gap seen in the previous integration row (`test/shared/fakes/fake_group_pubsub_network_test.dart`, `732/733`), classify it as unrelated/pre-existing and do not patch it in ML-007.
- Any failure in the new ML-007 direct, smoke, or `private_readd_current` criteria selector is ML-007-owned until triaged.
- Any GM overlap selector failure caused by shared ML-007 imports must be fixed before acceptance.
- A missing or unavailable iOS 26.2 live-device fixture blocks live proof; do not replace it with physical iOS, Android, macOS, Chrome, or a non-iOS-26.2 app peer.
- Existing dirty files are not failures unless the ML-007 execution edits or breaks them.

## done criteria

- The executor records whether ML-007 was already present, partial, or missing in main.
- Missing/partial imports are limited to row-owned ML-007 deltas in the six source-touched files.
- Production files stay untouched unless a focused ML-007 test proves a real row-owned production gap.
- Focused ML-007 direct, fake-network, and criteria selectors pass.
- Affected COMPLETE_1 preservation selectors for GM-006, GM-007, GM-008, GM-019, GM-021, and GM-024 pass or have accepted unrelated known-failure classification.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass or have accepted unrelated known-failure classification.
- Live `private_readd_current` proof passes if criteria/runner/harness are imported or changed.
- Minimal main integration docs are updated for INTEGRATE-ML-007 only.
- ML-008 remains untouched.

## scope guard

Do not duplicate COMPLETE_1 overlap coverage already present in main. Do not import generic `gm006` work as ML-007. Do not import adjacent or later re-add/churn/history/key/media scopes.

Explicit non-goals:

- `ML-008` repeated add-remove-re-add cycles.
- `ML-009` rapid remove/re-add ordering.
- `ML-011` duplicate/stale removal.
- history-retention and removed-window policy beyond ML-007's zero removed-window plaintext proof.
- GM-019 production recipient cutoff work unless focused ML-007 tests prove it.
- GM-021 key-package production fixes unless focused ML-007 tests prove it.
- GM-024 authoritative snapshot production fixes unless focused ML-007 tests prove it.
- source worktree doc updates.
- COMPLETE_1 doc updates.

## accepted differences / intentionally out of scope

- COMPLETE_1 GM rows remain their own accepted historical coverage and must not be reclosed by ML-007.
- Source ML-007 used the accepted multi-party harness prerequisite, but this integration row must still run its own live proof if harness/criteria/runner surfaces are imported or changed.
- Source ML-007 direct proof had a historical rerun with `-d macos` after a multiple-device command-shape issue; this integration plan still requires the user-requested focused command without adding broader device-discovery work.

## dependency impact

INTEGRATE-ML-008 remains the next pending row only after INTEGRATE-ML-007 is accepted, skipped as already present, or blocked with a concrete blocker. Do not advance to ML-008 during ML-007 planning or execution.

## reviewer findings

- Sufficiency: sufficient for execution as a minimal integration contract.
- Missing files, tests, or gates: none structurally missing; the executor must inspect the six source-touched files before import and run the listed focused/overlap commands.
- Stale assumptions: current marker scan suggests ML-007 is missing in main, but this is not enough to import blindly; file-by-file present/partial/missing classification is required.
- Overengineering: production edits and adjacent row imports are explicitly blocked unless focused ML-007 tests prove otherwise.
- Minimum needed: execute the checklist, import only missing row-owned deltas, run proof, and update minimal integration docs.

## arbiter decision

Structural blockers remaining: none.

Incremental details intentionally deferred: exact hunk selection is deferred to execution after the pre-application inspection.

Accepted differences intentionally left unchanged: COMPLETE_1 overlap rows stay separate; source ML-007 closure evidence is historical and not rerun during planning.

Why this plan is safe to implement now: it is bounded to one integration row, names exact source evidence and touched files, protects dirty main work through pre-application inspection, requires overlap preservation selectors, and keeps production untouched unless focused ML-007 tests prove a real gap.

## blockers

None for planning. Execution may still block on same-file dirty conflicts or unavailable iOS 26.2 live proof fixtures.

## Execution Progress

- 2026-05-17T21:05:00+02:00 - Contract extracted for exactly `INTEGRATE-ML-007`. Files inspected: source matrix row, source breakdown, source ML-007 plan/evidence, current plan, COMPLETE_1 overlap rows `GM-006`, `GM-007`, `GM-008`, `GM-019`, `GM-021`, and `GM-024`. Decision: this is import/reconcile/verify work only; do not recreate the source implementation plan and do not advance to ML-008.
- 2026-05-17T21:07:00+02:00 - Pre-application inspection completed. Current main had no `ML-007`, `private_readd_current`, `ml007ReaddCurrentProof`, or `ReaddCurrent` anchors in the six source-touched files. Classification: `integration_test/group_real_crypto_onboarding_test.dart` partial because the generic re-add crypto body existed but the ML-007 selector was missing; `test/features/groups/integration/group_membership_smoke_test.dart` partial because the generic fake-network re-add body existed but the ML-007 selector was missing; `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart` missing for ML-007/private_readd_current support.
- 2026-05-17T21:12:00+02:00 - Executor pass reconciled only missing/partial ML-007-owned deltas in the allowed files. Direct and smoke selectors were renamed to ML-007; `private_readd_current` criteria, accept/reject tests, runner listing, harness routing, Bob post-readd delivery, and `ml007ReaddCurrentProof` were added. Adjacent/later source scopes layered onto `private_readd_current` were omitted, including PL-004/PL-007/PL-011, RA-001/RA-002/RA-006/RA-007/RA-008/RA-009/RA-010/RA-014/RA-015/RA-016, KE-008/KE-009/KE-010/KE-011/KE-012, UP-001/UP-003, SV-003, history/media/reaction/key/churn, and later proof fields.
- 2026-05-17T21:14:00+02:00 - Formatted all six touched Dart files and analyzed them directly. Command: `dart analyze integration_test/group_real_crypto_onboarding_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`. Result: `No issues found!`.
- 2026-05-17T21:15:00+02:00 - Focused ML-007 selectors passed except the exact direct command without a device was environment/tooling blocked before test execution. Results: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` passed `+5`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-007'` passed `+1`; `flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'` failed before running because Flutter found multiple devices and required `-d`; `flutter test --no-pub -d macos integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'` passed `+1`.
- 2026-05-17T21:17:00+02:00 - COMPLETE_1 overlap preservation selectors passed. Smoke selectors passed: GM-006 `+1`, GM-007 `+1`, GM-008 `+1`, GM-019 `+1`, GM-021 `+1`, GM-024 `+1`. Criteria selectors passed: GM-006 `+5`, GM-007 `+6`, GM-008 `+7`, GM-019 `+5`, GM-021 `+4`, GM-024 `+5`.
- 2026-05-17T21:18:00+02:00 - Runner listing passed. Command: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios`. Result: `private_readd_current` was listed.
- 2026-05-17T21:25:29+02:00 - Live `private_readd_current` proof passed on available iOS 26.2 simulators. Command used current devices: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Result: `[ORCH] private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`. Run id: `1779045693458`. Logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_rM1NL2`.
- 2026-05-17T21:26:38+02:00 - Named gates and hygiene completed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed `+173`. `./scripts/run_test_gates.sh completeness-check` failed only on the known unrelated classification gap: `732/733 test files classified`, unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`. `git diff --check` passed. Post-live process scan found no active `run_group_multi_party_device_real`, `GROUP_MULTI_PARTY_SCENARIO`, `flutter drive`, or `xcodebuild` processes.
- 2026-05-17T21:31:17+02:00 - QA Reviewer completed read-only review. Verdict: accepted. Findings: no blocking issues; ML-007 anchors are isolated to the allowed test/harness surfaces; no ML-007 anchors in production/Go/pubspec/plist surfaces; exact blocked later row IDs are absent from the allowed files; overlap preservation evidence is sufficient.

## Final Execution Verdict

Verdict: `accepted`.

Changed paths owned by this row:

- `integration_test/group_real_crypto_onboarding_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-ML-007-plan.md`

Production files touched by this row: none. The worktree contains pre-existing dirty production/Go/package files, but `rg` found no ML-007/private_readd_current anchors in `lib`, `go-mknoon`, `pubspec.yaml`, `info.plist`, or other non-row-owned surfaces, and no production change was needed after focused ML-007 proof passed.

Final evidence:

- Focused ML-007 criteria selector passed: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` -> `+5`.
- Focused ML-007 fake-network selector passed: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-007'` -> `+1`.
- Required focused direct selector without `-d` failed before test execution because multiple devices were available and Flutter required a device. Same selector passed with explicit macOS device: `flutter test --no-pub -d macos integration_test/group_real_crypto_onboarding_test.dart --plain-name 'ML-007'` -> `+1`.
- COMPLETE_1 overlap smoke selectors passed for GM-006, GM-007, GM-008, GM-019, GM-021, and GM-024.
- COMPLETE_1 overlap criteria selectors passed for GM-006, GM-007, GM-008, GM-019, GM-021, and GM-024.
- Runner listing passed and included `private_readd_current`.
- Live iOS 26.2 `private_readd_current` proof passed with run id `1779045693458`; verdict path root `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_rM1NL2`.
- `dart analyze` on all six touched Dart files passed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed `+173`.
- `./scripts/run_test_gates.sh completeness-check` failed only on known unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification gap (`732/733`); this is external/pre-existing and does not block ML-007.
- `git diff --check` passed.
- QA Reviewer accepted with no blocking findings.

Skipped or omitted adjacent scope: no generic GM-006 import was accepted as ML-007; existing GM-006/GM-007/GM-008/GM-019/GM-021/GM-024 coverage was preserved. Later/private_readd_current source layers were intentionally omitted: PL-004/PL-007/PL-011, RA-001/RA-002/RA-006/RA-007/RA-008/RA-009/RA-010/RA-014/RA-015/RA-016, KE-008/KE-009/KE-010/KE-011/KE-012, UP-001/UP-003, SV-003, history/media/reaction/key/churn scopes, and later proof fields.

Blockers: none for ML-007. External known issue: completeness classification still has unrelated unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.

Next safe action: perform the separate closure/ledger update for `INTEGRATE-ML-007` if desired; do not infer ML-008 progress from this verdict.
