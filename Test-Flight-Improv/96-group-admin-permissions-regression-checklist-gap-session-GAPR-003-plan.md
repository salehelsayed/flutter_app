# GAPR-003 - Add System-Event And Convergence-Field Proof

Status: accepted

## Planning Progress

- `2026-05-29T12:39:47Z` - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, git status, and existing plan-path check. Decision/blocker: session id, source doc, accepted prerequisites, and intended plan path are confirmed; no existing GAPR-003 plan file was present. Next action: inspect the simulator harness, criteria validator, gate docs, and direct group event/pending-invite seams needed to plan evidence safely.
- `2026-05-29 14:44:00 CEST` - Local planning fallback completed after the spawned planner no-progressed past intake. Files inspected: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `lib/core/database/helpers/group_event_log_db_helpers.dart`, `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/groups/application/signed_group_transition_audit.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`, and existing criteria tests. Decision/blocker: current repo exposes enough harness-local surfaces for an implementation-ready proof plan without new schema or product feature work unless execution finds missing app-layer data. Next action: run downstream execution/QA.

## Real Scope

Add observable proof for Report 96's system-event visibility and richer convergence-field checklist, after GAPR-001 baseline stabilization and GAPR-002 forbidden-action proof are accepted.

In scope:

- Prove user-visible system/timeline events for:
  - Bob promotion
  - Charlie promotion
  - Bob demotion
  - Dana removal
- Expand active-peer convergence proof to include, where available:
  - `lastMetadataEventAt`
  - `lastMembershipEventAt`
  - latest local group-event/timeline identity or event text/hash evidence
  - pending invite count/state where relevant
  - removed-member representation after Dana removal
  - avatar metadata/bytes/hash
  - active members
  - admins
  - state hash
  - key epoch
- Tighten `integration_test/scripts/group_multi_party_device_criteria.dart` so the scenario-specific validator requires the new event/convergence proof fields and rejects older GAPR-002-only proof payloads.
- Add direct criteria tests in `test/integration/group_multi_party_device_criteria_test.dart` proving missing event proof and missing convergence fields fail.
- Add narrow helper/app tests only if execution proves an expected field is unavailable because of a repo-owned implementation gap.

Out of scope:

- New product-facing event UI or copy changes.
- Redefining admin policy or forbidden-action behavior already covered by GAPR-002.
- Final rollout verdict and stable docs reconciliation, which belong to GAPR-004.
- New database schema/migrations unless execution proves a required existing event/log field is impossible to observe without one. Current evidence indicates this should not be needed.
- Transport/libp2p changes.

## Closure Bar

This session is accepted only when:

- The four-user scenario emits system-event visibility proof for promotion, demotion, and member-removal events on relevant active members.
- Active roles prove convergence on metadata/membership event watermarks, pending-invite state where relevant, removed-member state after Dana removal, avatar metadata/bytes/hash, active members, admins, state hash, and key epoch.
- Criteria tests reject payloads missing the new event/convergence proof.
- The targeted reliability-sims scenario passes with GAPR-001, GAPR-002, and GAPR-003 proof enabled, or the session blocks with exact command, run id, shared dir, role, stage, and missing field.
- No final program verdict is claimed.

## Source Of Truth

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/features/groups/domain/models/group_model.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/application/signed_group_transition_audit.dart`
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart`

## Current Evidence

Available surfaces:

- `GroupModel` has `lastMembershipEventAt` and `lastMetadataEventAt`.
- The harness already uses `_timelineTexts(...)` and `_timelineOrderContains(...)`.
- The app has a durable group event log helper and signed transition audit payloads for `member_removed`, `member_role_updated`, and `group_metadata_updated`.
- Current `_regressionGroupSnapshot` records name, description, avatar metadata, members, admins, key epoch, and state hash.
- Current `_assertRegressionGroupStateConverged` compares state hash, key epoch, names, descriptions, and avatar hashes across active roles.
- Pending invite repos are local to role harnesses and can be queried before/after invite stages.
- GAPR-002 already records Alice-Dana no-invite proof and expanded rejected-action outcomes.

Current gaps:

- The proof object does not require visible promotion/demotion/removal timeline or event evidence.
- The proof object does not expose or compare `lastMetadataEventAt` and `lastMembershipEventAt` stage fields.
- Criteria does not require latest local event identity/text/hash evidence.
- Pending invite state is only partially represented by invite acceptance/no-invite logic and not summarized as part of convergence.
- Removed-member representation is final-state-only; criteria should require a field that explicitly proves Dana is represented as removed/excluded after removal.

## Implementation Plan

1. Preserve accepted prerequisite work.
   - Confirm GAPR-001 and GAPR-002 plans and ledger are accepted.
   - Inspect current diffs before editing and do not revert unrelated work.

2. Extend stage snapshot data.
   - Update the regression snapshot helper to include:
     - `lastMetadataEventAt`
     - `lastMembershipEventAt`
     - `latestGroupEventIdentity` or `latestGroupEventTextHash` if available from local messages/timeline/event log
     - pending invite count/state if a pending-invite repo is passed for that role/stage
     - removed-member peer ids or explicit removed/excluded proof where available
   - Keep existing fields and comparisons intact.
   - Add convergence checks for metadata and membership watermarks across active roles at stages where the relevant event is expected.

3. Add system-event/timeline proof helpers.
   - Use existing timeline/message helpers first. Expected user-visible text may be proven by event classification, normalized text, or stable text hash rather than brittle exact UI copy.
   - Add scenario-scoped helpers for:
     - `member_role_updated` promotion visible
     - `member_role_updated` demotion visible
     - `member_removed` removal visible
   - Prefer checking persisted system/timeline messages or event log entries already written by the app.
   - If exact display text is unstable, record stable fields such as event type, actor, target, event timestamp, and text hash.

4. Thread proof through role choreography.
   - Alice should prove Bob promotion, Charlie promotion, Bob demotion, and Dana removal events where relevant.
   - Bob should prove his promotion, Charlie promotion, his demotion, and Dana removal visibility while active.
   - Charlie should prove his promotion, Bob demotion, and Dana removal visibility where relevant.
   - Dana should prove events visible before removal as applicable and no active access after removal.
   - Do not add new successful control operations beyond existing choreography.

5. Add pending-invite convergence summaries.
   - Bob/Charlie/Dana pending invite repos should record pending count before accept and consumed/empty state after accept.
   - Alice non-friend Dana invite no-pending evidence from GAPR-002 should be preserved and included in the GAPR-003 convergence summary.
   - Criteria should require only meaningful pending-invite states; do not invent a global pending-invite convergence requirement for roles that do not own a pending repo at that stage.

6. Expand final proof object.
   - Add a `systemEventVisibilityProof` map keyed by event names, with per-role booleans or structured entries.
   - Add a `convergenceFieldProof` map summarizing the new stage fields, expected stages, and whether active roles matched.
   - Keep `stateConvergenceStages`, final metadata, final roles, active members, admins, removed member ids, state hash, key epoch, avatar fields, and rejected outcomes.

7. Tighten criteria.
   - Require `systemEventVisibilityProof` for promotion/demotion/removal events.
   - Require `convergenceFieldProof` to include metadata watermark, membership watermark, pending-invite state where meaningful, removed-member proof, avatar hash, state hash, key epoch, active members, and admins.
   - Add criteria tests:
     - valid expanded proof passes
     - missing promotion event proof fails
     - missing demotion event proof fails
     - missing removal event proof fails
     - missing metadata/membership watermark proof fails
     - missing pending-invite meaningful-state proof fails
     - missing removed-member representation proof fails

8. Verify.
   - Run direct criteria tests.
   - Run analyzer on harness/criteria/tests.
   - Run listing and discovery scripts.
   - Run targeted reliability-sims scenario.
   - Run `./scripts/run_test_gates.sh groups` and reclassify the known `UP-001` residual if unchanged.

## Files To Edit

Expected:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Conditional:

- `lib/core/database/helpers/group_event_log_db_helpers.dart` only if a small read-helper is missing and cannot be avoided with existing harness/timeline access.
- `lib/features/groups/application/group_membership_timeline_message.dart` only if existing classification cannot represent the event proof.
- Group application tests only if a current app-layer event or watermark is missing due to product behavior.

## Tests And Gates

Required direct checks:

```bash
dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart
dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios
./scripts/check_reliability_simulation_discovery.sh --records-tsv
./scripts/check_reliability_simulation_discovery.sh --checks-tsv
```

Required simulator closure:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Known residual handling:

- If the groups gate still fails only on `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`, record it as the existing non-target residual.
- Do not claim full group gate pass unless the gate is actually green.

Conditional direct tests:

```bash
flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/application/group_membership_update_listener_test.dart
```

Run only if touched or if the proof implementation exposes an app-layer defect there.

## Done Criteria

- `Status: execution-ready` is present before execution starts.
- GAPR-001 and GAPR-002 remain accepted and their proof is not weakened.
- System event visibility proof is present and criteria-enforced.
- Convergence field proof is present and criteria-enforced.
- Targeted reliability-sims scenario passes with all GAPR-001/GAPR-002/GAPR-003 proof.
- No GAPR-004 final program verdict is claimed.

## Scope Guard

Do not:

- Change user-facing event copy just to satisfy a test.
- Replace event visibility proof with only final-state convergence.
- Weaken GAPR-002 forbidden-action criteria.
- Add broad group reliability/product rewrites.
- Treat a missing final Report 96 verdict as a GAPR-003 blocker.

## Reviewer Findings

Review verdict: sufficient.

- The plan is not too broad because it touches one evidence seam: system-event and convergence proof within the already-running four-user scenario.
- The plan is not too narrow because criteria tests and targeted simulator closure are required, not just harness payload additions.
- The plan avoids GAPR-004 final acceptance and docs reconciliation.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Accepted differences:

- "Latest group event identity" may be represented by stable event type plus timestamp/source id/text hash rather than a DB auto-increment id if the harness cannot safely read a durable event-log row.
- "Group state version" may be represented by existing membership/metadata watermarks and signed transition state hash if there is no separate first-class version field in the current model.

## Execution Progress

- `2026-05-29T12:43:31Z` - Contract extracted. Files inspected: this plan, the session breakdown, source doc, skill instructions, git status, and current diffs for expected edit files. Decision/blocker: plan is execution-ready; scope is limited to system-event visibility and convergence-field proof; spawned-agent execution is available through `codex exec` with model `gpt-5.5` and `model_reasoning_effort=xhigh`. Next action: spawn Executor for the first implementation pass.
- `2026-05-29T12:45:39Z` - Executor started and contract extracted. Files inspected: this plan, `implementation-execution-qa-orchestrator` skill instructions, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, `GAPR-001` plan status, `GAPR-002` plan status, `git status --short`, and current diffs for the expected harness/criteria/test files. Decision/blocker: `GAPR-001` and `GAPR-002` are accepted; the worktree is dirty with prior accepted/session work plus unrelated deletions, so this pass will preserve existing modifications and scope edits to GAPR-003 proof unless an app-layer field gap is proven. Next action: inspect the current GAPR-002 proof seams and add missing event/convergence criteria regressions first.
- `2026-05-29T12:50:49Z` - Required RED criteria regression added and reproduced. Files touched: `test/integration/group_multi_party_device_criteria_test.dart`. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "regression group admin permissions rejects missing promotion event proof"` exit 1. Evidence: validator still returned `ok=true` after `systemEventVisibilityProof.bob_promotion` was removed from Alice's proof. Decision/blocker: GAPR-003 criteria enforcement is missing as planned. Next action: implement the narrow validator requirements, then thread equivalent proof through the harness payload.
- `2026-05-29T12:57:33Z` - Harness, criteria, and direct tests updated. Files touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Commands: `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0; `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 0; `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` exit 0 with 534 tests. Decision/blocker: direct structural checks are green and GAPR-003 criteria now reject missing system-event, watermark, pending-invite, and removed-member proof. Next action: run listing/discovery checks, then targeted simulator and groups gate.
- `2026-05-29T13:06:29Z` - Listing and discovery checks completed. Commands: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` exit 0 and listed `regression_group_admin_permissions_and_message_reliability_four_users`; `./scripts/check_reliability_simulation_discovery.sh --records-tsv` exit 0 and included the group runner; `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` exit 0 and included the regression scenario row; `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` exit 0 and resolved the target as check `#87`. Decision/blocker: discovery wiring is intact. Next action: run the targeted four-device simulator.
- `2026-05-29T13:06:29Z` - Targeted simulator closure passed. Command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exit 0. Evidence: run id `1780059522611`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_Fu0PQg`; orchestrator reported proof passed for `alice`, `bob`, `charlie`, and `dana`. Decision/blocker: GAPR-003 proof is emitted and accepted by the simulator criteria with GAPR-001/GAPR-002 proof preserved. Next action: run the named groups gate.
- `2026-05-29T13:06:29Z` - Named groups gate ran and retained the existing non-target residual. Command: `./scripts/run_test_gates.sh groups` exit 1 with final summary `+311 -1`. Triage command: `flutter test --no-pub -r expanded test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned"` exit 1. Evidence: targeted rerun reproduced `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`. Decision/blocker: this matches the plan's known residual policy and is not a GAPR-003 regression. Wrapper note: an initial shell wrapper using variable `status` failed before test execution because zsh treats `status` as read-only; the corrected rerun above is the classified evidence.
- `2026-05-29T13:06:29Z` - Executor pass complete. Files changed for this session scope: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Conditional app/helper files were not touched because existing model/timeline/pending-invite fields were sufficient. Remaining uncertainty: only the pre-existing UP-001 groups-gate residual; final Report 96 closure remains explicitly reserved for GAPR-004.

## Executor Result - GAPR-003

Executor verdict: ready for QA, with the named groups gate carrying the pre-existing non-target UP-001 residual only.

Code/test delta:

- Added scenario proof emission for role-scoped system event visibility, convergence watermark fields, pending-invite state summaries, removed-member representation, avatar bytes/hash proof, active/admin member sets, state hash, and key epoch.
- Tightened scenario criteria so missing promotion, demotion, removal, metadata/membership watermark, pending-invite, or removed-member proof is rejected.
- Added direct regression coverage for the new GAPR-003 criteria failures.

Commands and outcomes:

- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "regression group admin permissions rejects missing promotion event proof"` exit 1 before the fix, proving the missing criteria gap.
- `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 0.
- `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` exit 0 with 534 tests.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` exit 0.
- `./scripts/check_reliability_simulation_discovery.sh --records-tsv` exit 0.
- `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` exit 0.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` exit 0.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exit 0; run id `1780059522611`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_Fu0PQg`.
- `./scripts/run_test_gates.sh groups` exit 1 with `+311 -1`, classified by targeted rerun as the known UP-001 residual.
- `flutter test --no-pub -r expanded test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned"` exit 1 with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`.

Known residual classification:

- Existing non-target residual: `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` still fails with the documented stale membership event. No GAPR-003 files or proof paths were changed to mask it.

Remaining uncertainty:

- None within the GAPR-003 system-event and convergence-field scope. GAPR-004 still owns final Report 96 closure and program verdict.

## QA Review - GAPR-003

QA verdict: `blocked`

Files reviewed:

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `/tmp/gapr003-executor-1.txt`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

blocking issues:

- Latest group-event/timeline convergence is not actually proved or criteria-enforced. The source doc requires the latest event evidence shape to be observable and comparable across active members, and this plan includes latest local group-event/timeline identity or text/hash evidence in the active-peer convergence proof. The landed harness only records a stage when every active snapshot has any latest timeline event with a non-empty `messageId` and 64-character `textHash`; it does not compare event identity, event type, event timestamp, message id, or text hash across active roles. The validator then only requires `convergenceFieldProof.latestTimelineEventStages` to include `after_dana_removal`, so a payload with divergent latest event identities across active peers can still pass. Add a direct regression that fails on missing or drifted latest-event identity/hash proof, then make the harness and criteria require a stable comparable latest-event signature across the relevant active roles/stages.

non-blocking follow-ups:

- `./scripts/run_test_gates.sh groups` remains red only on the documented non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` residual with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`; this is permitted by the GAPR-003 plan and is not a blocker for this session after the targeted rerun classification.

QA evidence accepted:

- Required direct command evidence is present for both `dart analyze` commands, `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`, scenario listing, discovery records/checks, `run_with_devices.sh group --list`, and the targeted four-device simulator.
- Targeted simulator evidence is present: run id `1780059522611`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_Fu0PQg`, with proof reported for `alice`, `bob`, `charlie`, and `dana`.
- GAPR-001 and GAPR-002 plans remain `Status: accepted`; this review found no evidence that the GAPR-003 changes weakened their accepted proof. No GAPR-004 final program verdict was claimed.

Fix-pass required: yes. Recommended retry focus is the latest-event convergence proof and validator regression only; do not broaden into forbidden-action expansion or final closure.

## Fix-Pass #1 Progress - GAPR-003

- `2026-05-29T13:16:51Z` - Fix-pass contract inspected. Files inspected: this plan, `/tmp/gapr003-executor-1.txt`, `/tmp/gapr003-qa-1.txt`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: scope is limited to the QA-blocking latest timeline/event convergence proof; unrelated dirty worktree files and accepted GAPR-001/GAPR-002 changes are preserved. Next action: add the smallest direct criteria regression before implementation.
- `2026-05-29T13:16:51Z` - Required RED criteria regression added and reproduced. Files touched: `test/integration/group_multi_party_device_criteria_test.dart` and this plan. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "regression group admin permissions rejects drifted latest timeline event proof"` exit 1. Evidence: validator returned `ok=true` for Alice proof whose `convergenceFieldProof.latestTimelineEventProof.after_dana_removal.eventsByRole.bob.messageId` drifted from the other active roles. Decision/blocker: latest-event identity/hash proof is ignored by the current criteria, matching the QA blocker. Next action: emit comparable per-role latest-event proof from the harness and enforce stable `messageId`, `eventType`, `eventAt`, and `textHash` in criteria.
- `2026-05-29T13:29:34Z` - Latest timeline/event proof fix implemented. Files touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Harness now emits `convergenceFieldProof.latestTimelineEventProof` by stage with active roles, per-role comparable event data, and a stable signature over `messageId`, `eventType`, `eventAt`, and `textHash`; required stages are only marked present when active-role signatures converge. Criteria now requires `after_dana_removal` latest-event proof for Alice, Bob, and Charlie and rejects drifted or missing comparable fields. Direct criteria tests now cover drifted latest event proof, missing latest event proof, and missing latest event role proof. Decision/blocker: the QA-blocking latest-event convergence gap is fixed in code. Next action: complete focused validation.
- `2026-05-29T13:29:34Z` - Focused validation completed. Commands: `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "regression group admin permissions rejects drifted latest timeline event proof"` exit 0 after the fix; `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 0; `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` exit 0; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` exit 0 with 537 tests. Decision/blocker: direct format, analyzer, and criteria-test gates are green.
- `2026-05-29T13:29:34Z` - Targeted simulator closure completed. Command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exit 0. Resolved devices: one-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469`; two-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; role devices `alice=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `bob=5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `charlie=1B098DFF-6294-407A-A209-BBF360893485`, `dana=38FECA55-03C1-4907-BD9D-8E64BF8E3469`. Evidence: run id `1780060893842`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uB0JK3`; orchestrator reported proof passed for `alice`, `bob`, `charlie`, and `dana`; final script output reported `PASS: reliability simulations completed for scope: group`. Decision/blocker: GAPR-003 proof passes the targeted four-user scenario with GAPR-001/GAPR-002 proof preserved.
- `2026-05-29T13:29:34Z` - Optional groups gate classified. Command: `./scripts/run_test_gates.sh groups` exit 1 with final summary `+311 -1`. Triage command: `flutter test --no-pub -r expanded test/features/groups/integration/group_membership_smoke_test.dart --plain-name "UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned"` exit 1. Evidence: targeted rerun reproduced `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`. Decision/blocker: this is the known non-target UP-001 residual already allowed by the GAPR-003 plan; no new GAPR-003 blocker was found.

## Fix-Pass #1 Result - GAPR-003

Executor fix-pass verdict: ready for QA.

The QA blocking issue is addressed: latest group-event/timeline convergence is now emitted as comparable per-role proof and criteria-enforced for the required `after_dana_removal` active roles. Direct regression coverage proves drifted `messageId`, `eventType`, `eventAt`, or `textHash` evidence is rejected, and the targeted four-user simulator passes with the strengthened proof.

Residuals:

- `./scripts/run_test_gates.sh groups` remains red only on the known non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` residual, unchanged as `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`.
- GAPR-004 still owns final Report 96 checklist/program closure; this fix-pass does not claim final closure and did not update the breakdown ledger.

## QA Review - GAPR-003 Fix-Pass #1

QA verdict: `accepted`

Files reviewed:

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `/tmp/gapr003-executor-fix1.txt`
- `/tmp/gapr003-qa-1.txt`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Findings:

- The prior QA blocker is addressed. The harness now emits `convergenceFieldProof.latestTimelineEventProof` with per-role comparable latest-event fields and a stable signature over `messageId`, `eventType`, `eventAt`, and `textHash`; `after_dana_removal` is marked stable only when Alice, Bob, and Charlie converge on that signature.
- Criteria now requires the `after_dana_removal` latest-event proof for Alice, Bob, and Charlie and rejects missing or drifted `messageId`, `eventType`, `eventAt`, or `textHash` evidence.
- Direct criteria coverage includes missing latest-event proof, missing active-role proof, and drifted latest-event proof. QA reran `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "regression group admin permissions rejects drifted latest timeline event proof"` with exit 0.
- GAPR-001 and GAPR-002 remain `Status: accepted`; this review found no evidence that forbidden-action expansion was redone or weakened beyond keeping GAPR-002 criteria intact.
- No final Report 96 program verdict is claimed. The breakdown ledger still leaves GAPR-003 pending and GAPR-004 pending, as required for parent orchestration and final closure.

Residuals:

- `./scripts/run_test_gates.sh groups` remains red only on the known non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` residual, unchanged as `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`. This is non-blocking for GAPR-003 under the plan's known-residual policy.
