Status: accepted
Acceptance Status: accepted
Mode: standard worktree-to-main integration, not gap-closure
Source row: `ML-009 | Remove and re-add the same peer in rapid succession preserves event ordering`
Integration row: `INTEGRATE-ML-009`

# INTEGRATE-ML-009 Worktree-to-Main Integration Plan

## Planning Progress

- 2026-05-18 08:38:48 CEST - Evidence Collector started. Files inspected since last update: implementation-plan-orchestrator skill, `git status --short`, target plan path existence. Decision/blocker: target plan artifact did not exist; created intake stub only. Next action: inspect source ML-009 row/plan/evidence, main integration breakdown, and COMPLETE_1 preservation rows GM-011 through GM-014.
- 2026-05-18 08:40:47 CEST - Evidence Collector completed. Files inspected since last update: main integration breakdown, source matrix ML-009 row, source breakdown Session ML-009 block, source ML-009 plan/evidence, COMPLETE_1 GM-011/GM-012/GM-013/GM-014 rows, prior INTEGRATE-ML-006/007/008 contract style, current main marker scans, and current main iOS 26.2 device context from accepted ML rows. Decision/blocker: source ML-009 is historically accepted/covered; main INTEGRATE-ML-009 remains pending and marker scan found no `ML-009`, `private_rapid_readd`, or `ml009RapidReaddProof` anchors in the exact source-touched main files. Next action: draft standard integration contract.
- 2026-05-18 08:40:47 CEST - Planner completed. Files inspected since last update: exact source touched-file inventory, source proof commands, source live proof, current main GM-011..GM-014 preservation anchors, and prior current-device proof IDs. Decision/blocker: allow only missing/partial ML-009 rapid-ordering deltas; preserve GM-011..GM-014 and do not import ML-010/ML-011 or broader history/media/notification/key-epoch work. Next action: reviewer pass.
- 2026-05-18 08:40:47 CEST - Reviewer completed. Files inspected since last update: complete draft contract, scope guard, pre-application checklist, focused tests, preservation tests, live proof profile, known-failure interpretation, and next action. Decision/blocker: sufficient if execution performs fresh file-by-file classification before importing and does not treat source historical evidence as main acceptance. Next action: arbiter pass.
- 2026-05-18 08:40:47 CEST - Arbiter completed. Files inspected since last update: reviewer findings and closure bar. Decision/blocker: no structural blockers remain; this plan is execution-ready for INTEGRATE-ML-009 only, not accepted. Next action: execute later as a separate import/verification pass without moving to ML-010 or ML-011.

## Execution Evidence

- 2026-05-18 09:02 CEST - INTEGRATE-ML-009 executor completed in standard worktree-to-main integration mode. Fresh source-vs-main classification found `group_message_listener.dart` partial for source ML-009 explicit newer add/re-add membership ordering, `add_group_member_use_case.dart` already present for local admin bridge-sync behavior, and `test/shared/fakes/group_test_user.dart` already present for event timestamp support. Missing ML-009 row-owned tests, criteria, runner, and harness anchors were imported only for `private_rapid_readd`; GM-011, GM-012, GM-013, and GM-014 stayed preservation rows.
- Row-owned files accepted in main: `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart`; this integration plan; and the controlling integration breakdown.
- Focused ML-009 verification passed: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ML-009'` (`+1`); `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-009'` (`+1`); `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_rapid_readd'` (`+7`); `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart` (`+18`); `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios` included `private_rapid_readd`.
- COMPLETE_1 preservation verification passed: grouped `GM-011|GM-012|GM-013|GM-014` selectors in `group_message_listener_test.dart` (`+4`), `group_membership_smoke_test.dart` (`+4`), and `group_multi_party_device_criteria_test.dart` (`+25`); direct preservation selectors in `handle_incoming_group_message_use_case_test.dart` (`GM-013`, `+1`), `drain_group_offline_inbox_use_case_test.dart` (`GM-014`, `+1`), and `group_key_update_listener_test.dart` (`GM-014`, `+1`).
- Hygiene passed: `dart format` over the seven ML-009 Dart files completed; scoped `dart analyze` exited `0` with only pre-existing `use_null_aware_elements` info in `test/features/groups/application/group_message_listener_test.dart`; `git diff --check` passed.
- Fresh iOS 26.2 live proof passed: run id `1779087401421`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_rapid_readd_rzeYqB`, devices Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator detail `private_rapid_readd verdicts valid for alice, bob, charlie`. Role verdicts recorded matching active Alice/Bob/Charlie membership, matching config hash `6b8c909bf1a749a9b17c23e8fb94a10931f53fff483a497ffe24ae6fe2129b50`, final epoch `2`, Alice `readdIssuedBeforeRemovalAcks=true`, Bob `receivedRemovedWindowMessage=true` and `staleRemoveIgnored=true`, Charlie `removedWindowPlaintextCount=0`, and Charlie received both `alicePostRapidReadd` and `bobPostRapidReadd`.

## real scope

Process exactly `INTEGRATE-ML-009` for source row `ML-009 | Remove and re-add the same peer in rapid succession preserves event ordering`.

This is a worktree-to-main integration contract. It is not the original ML-009 implementation rollout, not gap-closure, and not a request to recreate or rewrite `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/.../Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md`. Reuse the source row, source breakdown, source plan/evidence, and source closure evidence only as historical source of truth.

Allowed execution deltas are only row-owned ML-009 deltas if current main is missing or partial:

- newer explicit add/re-add membership handling that prevents an older delayed `member_removed` from rolling Charlie back after rapid re-add;
- local admin membership watermark recording after successful add/re-add, only if current main lacks equivalent behavior;
- deterministic event timestamp support in `test/shared/fakes/group_test_user.dart`, only if needed for the imported tests;
- direct listener selector `ML-009 delayed older member_removed cannot roll back a rapid re-add`;
- fake-network selector `ML-009 rapid remove and re-add preserves latest membership ordering`;
- `private_rapid_readd` criteria, runner, and real-harness support;
- `ml009RapidReaddProof` validation and criteria rejection tests;
- focused `add_group_member_use_case_test.dart` coverage for the add/re-add watermark, if source-equivalent behavior is missing;
- minimal integration docs for this row only.

Out of scope: `ML-010`, `ML-011`, duplicate add/remove beyond preservation checks, timeline truth, history retention, media, notification, key epoch, UI, relay shared-state, stress/soak, and broader membership lifecycle work.

## closure bar

This plan is complete when a later executor can safely decide one of these outcomes for ML-009 only:

- `skipped_already_present`: all meaningful ML-009 anchors and behavior are already present in main, and focused ML-009 plus GM-011..GM-014 preservation selectors pass or receive accepted unrelated known-failure classification.
- `accepted`: missing or partial ML-009 deltas were integrated, focused ML-009 plus GM-011..GM-014 preservation selectors pass or receive accepted unrelated known-failure classification, required live proof is produced if harness/runner/criteria support is imported or changed, and the main integration ledger can be updated for INTEGRATE-ML-009 only.
- `blocked_conflict` or `blocked_external_fixture`: exact blocker is recorded without moving to ML-010, ML-011, or any later row.

This planning artifact itself is not acceptance evidence. Its status is `execution-ready`.

## source of truth

Authoritative sources for execution, in order:

1. Current main checkout code and tests, including existing dirty changes. Do not revert or overwrite unrelated edits.
2. Main integration breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
3. Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`.
4. Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`.
5. Source ML-009 plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md`.
6. Main COMPLETE_1 overlap breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.

COMPLETE_1 rows own their own main coverage. They are preservation constraints, not source import targets for ML-009.

## session classification

`implementation-ready` integration contract.

Execution must start from `execution-ready`, not `accepted`. Acceptance can happen only after a later executor performs fresh pre-application inspection, imports only missing/partial ML-009 deltas if needed, and runs the required proof.

## exact problem statement

Source ML-009 already proved the rapid-ordering contract: Charlie is active and online; Alice removes Charlie and immediately re-adds Charlie before Bob/Charlie process the earlier removal; Alice and Bob then send after the final re-add; every peer resolves to the latest membership operation; Charlie receives only post-readd messages and zero removed-window plaintext.

Main has COMPLETE_1 coverage for adjacent stale ordering and boundary rows, but INTEGRATE-ML-009 remains pending in the main integration breakdown. Planning-time marker scan found no `ML-009`, `private_rapid_readd`, `ml009RapidReaddProof`, or ML-009 selector anchors in the exact source-touched main files. GM-011..GM-014 anchors are present and must be preserved, not relabeled as ML-009.

## source ML-009 evidence

Source row exact contract:

| row | scenario | precondition | actions | expected |
|---|---|---|---|---|
| `ML-009` | Remove and re-add the same peer in rapid succession preserves event ordering | C is active and online. | A removes C, immediately re-adds C before all peers process removal, then A and B send. | Every peer resolves to the latest membership operation, and C receives messages only after the final re-add epoch. |

Historical source evidence only:

- Source status: `Covered` on 2026-05-12 by `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md`.
- Source production/support behavior: `group_message_listener.dart` lets an explicit newer add/re-add advance an existing member and membership watermark before a delayed older remove can roll state back; `add_group_member_use_case.dart` records the local admin membership watermark after successful add/re-add; `group_test_user.dart` supports event timestamp injection for deterministic rapid-ordering tests.
- Source direct proof: `group_message_listener_test.dart` selector `ML-009 delayed older member_removed cannot roll back a rapid re-add`.
- Source fake-network proof: `group_membership_smoke_test.dart` selector `ML-009 rapid remove and re-add preserves latest membership ordering`, using held deliveries and reverse release so re-add reaches Bob/Charlie before the older remove, then proving final member/key convergence, Bob removed-window receipt, Alice/Bob post-readd delivery to Charlie, and zero Charlie removed-window plaintext.
- Source criteria/harness proof: `private_rapid_readd` emits and validates `ml009RapidReaddProof`, rejecting missing proof, missing rapid-ordering fields, stale-remove application, removed-window plaintext leakage, missing Alice/Bob post-readd delivery, and final epoch/member divergence.
- Source evidence recorded as passed historically: listener selector `+1`, fake-network selector `+1`, `private_rapid_readd` criteria selector `+7`, `add_group_member_use_case_test.dart` `+16`, scoped analyzer exit `0` with only pre-existing harness style infos, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` `+134`, `./scripts/run_test_gates.sh completeness-check` `732/732`, exact-relay live `private_rapid_readd` run `1778542395575`, and `git diff --check`.
- Source live proof path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_rapid_readd_Vdnom9`.
- Source live app peers: Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.
- Source live verdicts recorded Alice removing and re-adding before removal acknowledgements, Bob receiving the removed-window message while ignoring stale remove after re-add, all roles finishing at epoch `2` with Alice/Bob/Charlie active and identical config hash, Charlie receiving Alice/Bob post-readd messages, and Charlie `removedWindowPlaintextCount=0`.

Do not claim any of these source tests have passed in main.

## exact source touched files

Source ML-009 implementation/proof touched these code/test/harness files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Source ML-009 closure also updated source docs. Do not import those docs wholesale:

- `Private_group_chat_reliability_test_matrix_full_with_rules.md`
- `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md`

## likely main classifications from planning

Planning-time marker scan in current main found no ML-009 row anchors in the exact source-touched files. This is not final execution classification, but it guides the next pass:

| file or surface | planning-time likely classification | reason |
|---|---|---|
| `lib/features/groups/application/group_message_listener.dart` | likely partial or missing for ML-009 | No ML-009 marker; GM-013/GM-014 preservation behavior exists elsewhere and may already satisfy some ordering mechanics. Fresh diff inspection required before any production import. |
| `lib/features/groups/application/add_group_member_use_case.dart` | likely missing ML-009 row marker | No ML-009 marker found. Import watermark behavior only if current main lacks source-equivalent admin add/re-add watermarking. |
| `test/shared/fakes/group_test_user.dart` | likely partial or missing for ML-009 | No ML-009 marker found. Import event timestamp support only if the ML-009 tests need it and equivalent helper support is absent. |
| `test/features/groups/application/group_message_listener_test.dart` | likely missing ML-009 selector | GM-011/GM-012/GM-013/GM-014 selectors exist, but no ML-009 direct selector was found. |
| `test/features/groups/application/add_group_member_use_case_test.dart` | likely missing ML-009-specific watermark proof | No ML-009 marker found. Existing add-member tests must be preserved. |
| `test/features/groups/integration/group_membership_smoke_test.dart` | likely missing ML-009 fake-network selector | GM-011/GM-012/GM-013/GM-014 selectors exist, but no ML-009 rapid remove/re-add selector was found. |
| `integration_test/scripts/group_multi_party_device_criteria.dart` | likely missing `private_rapid_readd`/`ml009RapidReaddProof` | GM-011..GM-014 criteria exist; no ML-009 scenario/proof marker found. |
| `test/integration/group_multi_party_device_criteria_test.dart` | likely missing `private_rapid_readd` criteria tests | GM-011..GM-014 criteria tests exist; no ML-009 criteria marker found. |
| `integration_test/scripts/run_group_multi_party_device_real.dart` | likely missing `private_rapid_readd` runner support | Runner lists `private_readd_current` and `private_readd_cycles`, plus GM-011..GM-014, but no `private_rapid_readd` marker found. |
| `integration_test/group_multi_party_device_real_harness.dart` | likely missing `private_rapid_readd` role/proof support | GM-011..GM-014 harness support exists; no ML-009 scenario/proof marker found. |

Execution must rerun this classification immediately before editing, because the main worktree is dirty and other agents may change these files.

## COMPLETE_1 preservation comparison

| COMPLETE_1 row | overlap with ML-009 | preservation rule |
|---|---|---|
| `GM-011` | Remove then stale add arrives out of order; final membership remains removed and stale add does not resurrect Charlie or old keys. | Preserve GM-011 stale-add-after-remove proof. Do not import, rename, or relabel `gm011StaleAddRemovalProof` as ML-009. ML-009 must not weaken Charlie removal exclusion or A/B delivery after stale add. |
| `GM-012` | Add then stale remove arrives out of order; final membership remains re-added only if newer version wins, old remove does not strand Charlie. | Preserve GM-012 stale-remove-after-readd proof. ML-009 is close but not identical: it owns the rapid remove/re-add row and `private_rapid_readd`, not generic `gm012` proof. |
| `GM-013` | Simultaneous admin remove and member send; deterministic removal cutoff accepts before-cutoff sender content and rejects after-cutoff content. | Preserve cutoff behavior and `GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF` expectations. ML-009 imports must not roll back removal cutoff preservation or before/after cutoff tests. |
| `GM-014` | Simultaneous re-add and sender send; Charlie decrypts from membership start or receives explicit key repair, with no silent loss. | Preserve shared re-add `eventAt`/`joinedAt`, delayed key/config catch-up, no duplicate durable recipients, no duplicate topic joins, and zero removed-window plaintext. Do not treat GM-014 delayed-key proof as ML-009 closure. |

## files and repos to inspect next

Pre-application inspection must compare source and main for these exact ML-009 files before any import:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Inspect these COMPLETE_1 preservation owner files before changing shared behavior:

- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

## existing tests covering this area

Main already has adjacent COMPLETE_1 preservation coverage:

- `GM-011` stale add after remove stays removed.
- `GM-012` stale remove after re-add stays re-added and current.
- `GM-013` simultaneous remove/send cutoff preservation.
- `GM-014` simultaneous re-add/send delayed key/config catch-up.

These are preservation tests only. They do not replace ML-009 row-owned `private_rapid_readd`, rapid ordering proof, or `ml009RapidReaddProof`.

## regression/tests to add first

Do not add from scratch until the pre-application checklist classifies each ML-009 delta. If missing or partial, import only these source-owned regressions/proof surfaces:

- `group_message_listener_test.dart`: `ML-009 delayed older member_removed cannot roll back a rapid re-add`;
- `group_membership_smoke_test.dart`: `ML-009 rapid remove and re-add preserves latest membership ordering`;
- `add_group_member_use_case_test.dart`: source-equivalent local admin watermark proof, if current main lacks it;
- `private_rapid_readd` scenario support in criteria, runner, and harness;
- `ml009RapidReaddProof` emitted for Alice/Bob/Charlie with row id `ML-009`;
- criteria tests that accept valid proof and reject missing proof, weak rapid-ordering fields, stale-remove application, removed-window plaintext, missing Alice/Bob post-readd delivery, and final epoch/member divergence.

## row-owned import rules

1. Run `git status --short` and record existing dirty files.
2. For each exact source-touched file, inspect `git diff -- <file>` in main and preserve unrelated edits.
3. Search current main and source for `ML-009`, `private_rapid_readd`, `ml009RapidReaddProof`, `RapidReadd`, `delayed older member_removed`, `rapid remove`, `rapid re-add`, and the exact source selector names.
4. Classify every file as `already_present`, `partial`, or `missing`.
5. If all ML-009 behavior and anchors are already present, skip import and run proof only.
6. If partial, import only missing ML-009 anchors and reconcile with current main helpers.
7. If missing, import only the row-owned source hunks listed in this plan.
8. Production changes are allowed only for source-proven ML-009 ordering/watermark behavior and only if current main lacks equivalent behavior.
9. Preserve GM-011, GM-012, GM-013, and GM-014 behavior and proof fields.
10. Do not import `ML-010`, `ML-011`, `private_duplicate_remove`, `private_timeline_truth`, history-retention, media, notification, key-epoch, or later source proof fields.
11. Do not update source worktree docs or COMPLETE_1 docs during this integration row.

## step-by-step implementation plan

1. Perform the pre-application inspection checklist and record file classifications.
2. Decide `already_present`, `partial`, or `missing` for ML-009.
3. If already present, do not import; run focused ML-009 proof and GM-011..GM-014 preservation selectors.
4. If partial, import only missing ML-009 row anchors and minimal missing behavior.
5. If missing, import only the exact ML-009 files/proof fields listed above.
6. Reconcile shared criteria/runner/harness maps without renaming or weakening GM-011..GM-014.
7. Run focused ML-009 tests.
8. Run GM-011..GM-014 preservation selectors because shared membership ordering and harness surfaces are touched.
9. If criteria/runner/harness support was imported or changed, run the live `private_rapid_readd` proof.
10. Run named gates and hygiene.
11. Update only the main integration row docs/ledger for INTEGRATE-ML-009 after proof. Stop without moving to ML-010 or ML-011.

## risks and edge cases

- The main worktree is heavily dirty; source hunks must not overwrite unrelated edits.
- GM-012 is similar to ML-009 but is not equivalent. ML-009 must keep a distinct rapid remove/re-add scenario and proof field.
- GM-013/GM-014 cutoff and membership-start behavior can be broken by careless `joinedAt` or watermark changes.
- Criteria/runner/harness maps are shared across many accepted rows; adding `private_rapid_readd` must not disturb scenario lists or role dispatch for GM rows.
- If current main already includes equivalent production behavior under GM-014 or later shared fixes, execution should import only missing ML-009 tests/harness proof.
- Device availability is not stable; executor must refresh simulator availability and block truthfully if the required iOS 26.2 app-peer profile cannot run.

## exact tests and gates to run

Focused ML-009 commands:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ML-009'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-009'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_rapid_readd'
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios
dart analyze lib/features/groups/application/group_message_listener.dart lib/features/groups/application/add_group_member_use_case.dart test/shared/fakes/group_test_user.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart
```

GM-011..GM-014 preservation selectors:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-011'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-012'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-013'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-014'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-011'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-012'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-013'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-014'
```

Named gates and hygiene:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## live three-party device/relay proof profile

Required if `private_rapid_readd` criteria, runner, or harness support is imported or changed. Also recommended if execution classifies row behavior as already present but needs final main-side proof.

Before running, refresh current devices:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Use only iOS 26.2 CoreSimulator app peers. Current main integration context records these available iOS 26.2 devices from recent accepted ML rows:

- Alice: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob: `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

If these are not currently available as iOS 26.2 simulators, either use the refreshed iOS 26.2 CoreSimulator IDs and record the substitution, or block as `blocked_external_fixture`. Do not substitute physical iOS, Android, macOS, Chrome, iOS 26.1, iOS 26.4, or any non-iOS-26.2 app peer.

Live command profile:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_rapid_readd -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Do not claim live proof has passed until a later executor actually runs it and records run id, shared dir, verdict files, role verdict facts, and device IDs.

## known-failure interpretation

No tests were run during this planning-only pass.

During execution, a `completeness-check` failure may be classified as unrelated only if it is exactly the pre-existing unclassified `test/shared/fakes/fake_group_pubsub_network_test.dart` gap or another already-recorded non-ML-009 classification gap, and no ML-009 touched file is implicated. Any focused ML-009 failure, GM-011..GM-014 preservation failure, row-owned analyzer error, live proof failure, or new completeness gap in an ML-009 touched file is a blocker for acceptance.

Source analyzer notes about pre-existing harness style infos are historical only. Do not treat new analyzer output as accepted without exact current evidence.

## done criteria

- Current main is inspected and every exact source-touched file is classified as `already_present`, `partial`, or `missing`.
- Any import is limited to ML-009 row-owned files, anchors, proof fields, and minimal behavior named in this plan.
- GM-011, GM-012, GM-013, and GM-014 preservation selectors remain green or have accepted unrelated failure classification.
- Focused ML-009 selectors and required gates produce accepted current-main evidence.
- Live `private_rapid_readd` proof runs on iOS 26.2 CoreSimulator app peers if harness/runner/criteria support is imported or changed, or execution records a defensible already-present reason for not rerunning.
- Integration docs/ledger update only INTEGRATE-ML-009.
- No ML-010, ML-011, history, media, notification, key-epoch, or broader lifecycle scope is imported or claimed.

## scope guard

Preserve dirty worktree changes. Do not stage, commit, revert, reset, or overwrite unrelated files. If an exact ML-009 target file is already dirty, inspect and merge around existing edits; do not replace the file from the source worktree.

Do not recreate or rewrite the original source ML-009 implementation plan. Do not copy source matrix, source breakdown, source test inventory, or COMPLETE_1 docs into main as part of this row. The only plan artifact created by this planning pass is this worktree-to-main integration contract.

## accepted differences / intentionally out of scope

- GM-011..GM-014 remain accepted COMPLETE_1 rows with their own proof fields and scenario names.
- If current main already has equivalent production behavior from GM-014 or later shared fixes, ML-009 may be a tests/harness-only import plus verification.
- Historical source device IDs `560D3E2D-78F8-4D28-A010-16B399581C99`, `511B36DA-7113-41A7-A718-4450C87C0E62`, and `DE36DBBE-64FC-4652-AAD9-17329A1BA245` are source proof context, not mandatory current-device IDs if unavailable.
- `ML-010`, `ML-011`, duplicate add/remove row closure, timeline truth, history retention, notifications, media, key-epoch, stress, and UI work remain separate integration rows.

## dependency impact

INTEGRATE-ML-010 and INTEGRATE-ML-011 must not start from this row. They may proceed only after INTEGRATE-ML-009 is accepted, skipped as already present with proof, or blocked with a precise blocker that the pipeline controller explicitly handles.

Later rows that depend on rapid remove/re-add ordering should rely on the final INTEGRATE-ML-009 ledger outcome, not this planning artifact.

## final verdict

Final verdict: accepted for INTEGRATE-ML-009 only.

Structural blockers remaining: none.

Accepted row-owned delta: explicit newer add/re-add membership convergence in `group_message_listener.dart`, ML-009 direct and fake-network tests, `private_rapid_readd` criteria/runner/harness support, `ml009RapidReaddProof` validation, and row integration docs.

Accepted differences intentionally left unchanged: GM-011..GM-014 remain preservation rows and are not imported, renamed, weakened, or relabeled as ML-009. `add_group_member_use_case.dart` and `test/shared/fakes/group_test_user.dart` were already source-equivalent for this row and were not modified by ML-009.

Exact docs/files used as evidence: the main integration breakdown, source ML-009 matrix row, source session breakdown, source ML-009 plan/evidence, COMPLETE_1 GM-011..GM-014 breakdown rows, fresh current-main file classifications, focused selector output, preservation selector output, scoped analyzer/format/diff checks, and fresh live proof run `1779087401421`.

Next action: resume the pipeline at INTEGRATE-ML-010. Do not treat this accepted ML-009 row as ML-010, ML-011, history, media, notification, key-epoch, or broader lifecycle scope.
