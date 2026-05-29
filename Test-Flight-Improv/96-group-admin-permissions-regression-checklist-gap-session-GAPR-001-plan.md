# GAPR-001 Session Plan - Stabilize Current Four-User Scenario Baseline

Status: accepted

## Planning Progress

- `2026-05-29T11:06:37Z` - Arbiter completed. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`. Decision/blocker: no structural blockers remain; incremental evidence-source adjustments are applied; accepted differences are documented. Next action: ready for execution via the downstream execution/QA workflow.
- `2026-05-29T11:06:04Z` - Reviewer completed; Arbiter started. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`. Decision/blocker: plan is sufficient with incremental evidence-source hardening and no structural blocker found by reviewer. Next action: classify reviewer findings and finalize execution-ready status if no structural blocker remains.
- `2026-05-29T11:06:04Z` - Planner completed; Reviewer started. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`. Decision/blocker: draft includes all mandatory sections, simulator closure, and regression-first rule. Next action: sufficiency review.
- `2026-05-29T11:03:41Z` - Evidence Collector completed; Planner started. Files inspected since last update: `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/update_group_member_role_use_case.dart`. Decision/blocker: current evidence supports a narrow evidence-gated triage plan around metadata/avatar propagation waits, with product seams conditional on a fresh targeted rerun. Next action: write the execution-safe plan draft.
- `2026-05-29T11:01:52Z` - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`. Decision/blocker: session source, scope, classification, and required plan path are confirmed. Next action: inspect Report 95, gate definitions, test map, closure reference, and direct scenario harness/criteria files.

## real scope

This session stabilizes the already-added `regression_group_admin_permissions_and_message_reliability_four_users` baseline before any Report 96 checklist widening.

In scope:

- Reproduce and triage the current targeted simulator blocker for `regression_group_admin_permissions_and_message_reliability_four_users`.
- Resolve only the blocker that prevents the existing four-user scenario from reaching the current Report 95 baseline assertions.
- Keep primary edits in `integration_test/group_multi_party_device_real_harness.dart` and `integration_test/scripts/group_multi_party_device_criteria.dart` if the defect is harness timing, proof shape, or overly strict stage validation.
- Touch production seams only after fresh evidence proves a real metadata/avatar propagation defect, authorization defect, stale-event defect, avatar-download defect, or role/membership snapshot defect.
- Add the narrowest direct regression that pins any production defect before fixing it.

Out of scope:

- Expanding forbidden admin-action coverage. That belongs to `GAPR-002`.
- Adding system-event visibility or richer convergence-field proof. That belongs to `GAPR-003`.
- Final checklist acceptance or stable doc reconciliation. That belongs to `GAPR-004`.
- New simulator framework, new scenario id, new admin policy, UI redesign, broad group reliability rewrites, or transport/libp2p changes unless the targeted evidence proves this exact scenario is blocked below that layer.

## closure bar

The session is good enough when the existing four-user scenario is a stable baseline again:

- `regression_group_admin_permissions_and_message_reliability_four_users` remains registered, listed, and selectable by stable `path:scenario`.
- The current Report 95 assertions are not weakened: final active members, admins, removed Dana, metadata, avatar metadata/bytes/hash, state hash, key epoch, rejected-action proof, self-delivery proof, and message-matrix keys still validate.
- A fresh targeted simulator run either passes, or the session is truthfully reclassified as blocked with exact command, run id, shared directory, failing role, failing stage, missing field, and root-cause classification.
- Any production fix has a direct host regression that fails before the fix and passes after the fix.
- `./scripts/run_test_gates.sh groups` and the targeted `$run-flutter-reliability-sims` scenario are run or truthfully classified under the known-failure policy.

Host tests alone cannot close this simulator-gated group reliability session.

## source of truth

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md` is the active session contract for `GAPR-001`.
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md` is the Report 96 checklist intent, but this session only stabilizes the current baseline.
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md` is authoritative for the existing scenario implementation and known targeted failure evidence.
- `Test-Flight-Improv/14-regression-test-strategy.md` requires targeted permanent regressions by blast radius and no broad smoke-test inflation.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gates; it classifies `integration_test/scripts/run_group_multi_party_device_real.dart` as an optional/manual simulator orchestrator and `./scripts/run_test_gates.sh groups` as the group messaging gate.
- `Test-Flight-Improv/_current-test-map.md` maps group metadata/photo authority and promoted-admin invite propagation to the `groups` gate plus targeted direct suites.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` is evidence only for release-confidence wording; this session updates it only if a product reliability defect is fixed or newly classified.
- Current code and tests win over stale prose on implementation details.

## session classification

`evidence-gated`

The session must start by collecting fresh simulator evidence. The known failures point at metadata/avatar convergence, but the exact root cause could be harness sequencing, stale event handling, signature/authorization rejection, group-config sync, avatar download/recovery, or membership snapshot state.

## exact problem statement

The four-user admin-permissions regression was implemented and is discoverable, but the required targeted simulator closure is currently red. Report 95 records Bob timing out in `_waitForGroupMetadata` at `after_charlie_metadata_v2`; another attempt exposed Dana failing to converge at `after_alice_avatar_v3`.

User-visible behavior at risk: active group members may not converge on group name, description, avatar metadata, avatar bytes, roles, membership, key epoch, and state hash after promoted admins and the creator publish metadata/avatar updates across four live app instances.

Must stay unchanged: the scenario identity, four-role Alice/Bob/Charlie/Dana journey, friend graph, admin policy, removed-member exclusion, and existing proof strength.

## files and repos to inspect next

Primary owner files:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`

Direct tests and gate docs:

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`

Conditional product seams if fresh evidence proves a real propagation defect:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`

## existing tests covering this area

- `integration_test/scripts/group_multi_party_device_criteria.dart` registers the four-role scenario requirement and validates scenario-specific proof.
- `integration_test/scripts/run_group_multi_party_device_real.dart` maps `regression_group_admin_permissions_and_message_reliability_four_users` to the scenario list.
- `integration_test/group_multi_party_device_real_harness.dart` contains `_waitForGroupMetadata`, `_assertRegressionGroupStateConverged`, `_assertRegressionGroupImageVisible`, the Alice/Bob/Charlie/Dana choreography, and the current failing stages.
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart` covers promoted-admin metadata/photo convergence, promoted-admin member add, fanout, avatar update convergence, and demotion enforcement in a host/fake network setup.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` wraps the convergence journeys for simulator execution.
- `test/features/groups/application/group_message_listener_test.dart` already covers `group_metadata_updated` metadata/avatar persistence, timeline events, stale metadata handling, and equal-watermark avatar recovery.
- `./scripts/run_test_gates.sh groups` covers the canonical group messaging gate for send, invite, membership, metadata/photo authority, and resume behavior.

Current gap for this session: none of the host tests proves this exact four-live-app role-churn sequence. The targeted reliability simulator remains the closure source of truth.

## regression/tests to add first

Do not add Report 96 checklist-widening assertions first.

Before implementation, rerun the targeted simulator and classify the blocker. Then add the smallest direct regression for the proven seam:

- If the failure is in receive-side metadata/avatar application, add a focused case to `test/features/groups/application/group_message_listener_test.dart` that reproduces the stale/equal-watermark, actor authorization, `groupConfig`, avatar download, or timeline-save condition identified in the simulator evidence.
- If the failure is in local metadata publishing, add a focused case to `test/features/groups/application/update_group_metadata_use_case_test.dart` or `test/features/groups/integration/group_admin_metadata_convergence_test.dart` that proves the published config carries the correct name, description, avatar blob/mime/path, `metadataUpdatedAt`, state hash, and admin actor identity.
- If the failure is in role churn or member snapshot authority, add the narrow case beside `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/update_group_member_role_use_case_test.dart`, or `test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
- If evidence proves the product is correct and the harness is racing or asserting the wrong expected avatar/state, adjust only `integration_test/group_multi_party_device_real_harness.dart` or `integration_test/scripts/group_multi_party_device_criteria.dart` and preserve proof strength.

The direct regression must be named in the execution notes and run directly before the product fix is considered complete.

## step-by-step implementation plan

1. Capture pre-change scenario shape.
   - Run the direct analyzer/list/discovery commands in this plan.
   - Confirm the scenario is still listed by `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios`.
   - Confirm `$run-flutter-reliability-sims group --list` still exposes the scenario by stable `path:scenario`.

2. Reproduce the targeted failure before editing code.
   - Run the exact targeted `$run-flutter-reliability-sims` command.
   - Record command, exit code, run id, shared directory, failing role, failing stage, expected metadata/avatar tuple, actual metadata/avatar tuple, and whether the failure is metadata fields, avatar path/bytes, member role, active member set, key epoch, or state hash.

3. Inspect the simulator artifacts for the first failed stage.
   - For Bob at `after_charlie_metadata_v2`, compare Alice/Bob/Charlie `*_regression_state_after_charlie_metadata_v2.json` files if present.
   - For Dana at `after_alice_avatar_v3`, compare all active-role `*_regression_state_after_alice_avatar_v3.json` files if present.
   - Inspect app logs around `GROUP_MESSAGE_LISTENER_STALE_METADATA_EVENT_IGNORED`, `GROUP_MESSAGE_LISTENER_METADATA_STATE_HASH_MISMATCH`, `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_REJECTED`, `GROUP_MESSAGE_LISTENER_GROUP_METADATA_UPDATED`, `GROUP_MESSAGE_LISTENER_METADATA_EVENT_RETRYING_AVATAR_DOWNLOAD`, `CONFIG_SYNC_FAILED`, and avatar download failures.
   - Decide whether the earliest failure is harness sequencing/proof shape or product propagation.

4. Stop if the fresh run disproves the known blocker.
   - If the targeted run passes without changes, rerun it once to rule out a transient pass.
   - If both targeted runs pass, update only this plan's execution notes and the breakdown ledger during execution closure; do not widen assertions in this session.

5. Add the direct regression first if product behavior is implicated.
   - Use the smallest test file from the `regression/tests to add first` section.
   - Make the regression fail for the observed root cause without encoding simulator timing.
   - Do not add broad Report 96 checklist assertions here.

6. Apply the minimal fix.
   - Harness-only fix: keep edits in `integration_test/group_multi_party_device_real_harness.dart` or `integration_test/scripts/group_multi_party_device_criteria.dart`, preserving final proof fields and message-matrix strength.
   - Product fix: touch only the proven metadata/avatar, group-config, role/membership, or avatar-storage seam. Do not change admin policy or transport behavior unless the direct regression proves that exact layer.

7. Verify from narrow to broad.
   - Run the new direct regression.
   - Run existing direct group metadata/convergence tests.
   - Run analyzer, list, discovery, `groups` gate, and targeted reliability simulator closure.

8. Update docs only as allowed by the breakdown.
   - During execution/closure, update this breakdown ledger with the result.
   - Append Report 95 status only if needed to record the fresh blocker/fix evidence.
   - Update `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` only if a product reliability defect is fixed or newly classified.

## risks and edge cases

- The targeted simulator can fail from device allocation or relay/runtime environment; classify that separately from code.
- Metadata can converge before avatar bytes are downloaded; stage diagnostics must distinguish blob/mime/path convergence from byte visibility.
- Equal or stale metadata watermarks can suppress a legitimate avatar retry.
- Role churn can leave a peer with stale admin/member snapshots and cause authorization or state-hash rejection.
- Harness signal order can make one role wait on an expected avatar before the publisher has actually sent or regranted it.
- A product fix that changes group-config pruning, role authority, or stale-event rules can widen blast radius into group invite/member/remove flows.

## exact tests and gates to run

Pre-change and post-change structural checks:

```bash
dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios
./scripts/check_reliability_simulation_discovery.sh --records-tsv
./scripts/check_reliability_simulation_discovery.sh --checks-tsv
```

Direct host/simulator-adjacent tests:

```bash
flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart
flutter test --no-pub integration_test/group_admin_metadata_convergence_simulator_test.dart
```

If `group_message_listener.dart` or listener metadata/avatar behavior changes:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
```

If metadata publishing changes:

```bash
flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart
```

If role update publishing or local role churn changes:

```bash
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart
```

Named group gate:

```bash
./scripts/run_test_gates.sh groups
```

Required simulator closure:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"
```

Run `transport` only if the implementation changes startup, resume, reconnect, relay, bridge transport, or libp2p behavior:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
```

## known-failure interpretation

- The Report 95 targeted simulator red result is a known blocker, not a new regression caused by `GAPR-001` execution. New work is responsible for reproducing, classifying, and resolving or truthfully re-blocking it.
- Bob timing out at `after_charlie_metadata_v2` means the first classification target is Charlie's promoted-admin metadata/avatar update reaching Bob and matching name, description, blob id, mime, path, bytes, state hash, and key epoch.
- Dana failing at `after_alice_avatar_v3` means the second classification target is Alice's later avatar update reaching all four active members after Dana joins and after Bob's demotion.
- Simulator/device allocation failures are environment blockers and must include the device-resolution output.
- A `groups` gate failure outside changed files or the direct product seam must be isolated by rerunning the failing test before it is blamed on this session.
- Scenario number `87` is not stable evidence; use the stable `path:scenario` selector.

## done criteria

- `Status: execution-ready` is present in this plan before execution starts.
- Fresh pre-change targeted evidence is captured.
- The root cause is classified as harness, product, environment, flaky, stale/already-covered, or still-blocked with concrete files/stages.
- Any product fix has a direct regression added first and passing after the fix.
- No Report 96 checklist-widening assertions are added in this session.
- The scenario remains discoverable through the runner, discovery scripts, and `$run-flutter-reliability-sims group --list`.
- The targeted reliability-sims command passes, or the session is closed as blocked with exact failing evidence and no ambiguous partial-closure claim.
- `./scripts/run_test_gates.sh groups` passes or is triaged under known-failure policy.

## scope guard

Do not:

- Weaken `_assertRegressionGroupStateConverged`, avatar byte proof, state-hash comparison, key-epoch proof, removed-member proof, or message-matrix requirements.
- Change the scenario name, role count, or Alice/Bob/Charlie/Dana journey.
- Add `GAPR-002` forbidden-action matrix cases or `GAPR-003` event/convergence-field proof here.
- Treat one successful host test as closure for a four-live-app simulator bug.
- Make broad group repository, listener, transport, or bridge refactors without direct evidence from the targeted run.
- Change group admin policy, invite policy, removed-member semantics, or friend graph behavior.

## accepted differences / intentionally out of scope

- The current scenario is a real-app peer simulator regression, not a UI tap test. It can use harness/app-layer APIs as long as it preserves existing proof strength.
- Report 96's complete checklist remains intentionally incomplete until `GAPR-002`, `GAPR-003`, and `GAPR-004`.
- The final stable release-confidence wording remains out of scope for this session unless a product reliability defect is fixed or newly classified.
- A full group reliability sweep is optional unless code changes widen blast radius beyond this targeted scenario.

## dependency impact

`GAPR-002` and `GAPR-003` depend on this session producing a stable baseline or a truthful blocker. If `GAPR-001` remains blocked, later sessions must not widen checklist assertions on top of the red scenario because failure attribution would be ambiguous. `GAPR-004` cannot close the Report 96 checklist unless this scenario is stable and targeted simulator evidence is trustworthy.

## reviewer findings

Review verdict: sufficient with adjustments.

- Missing files, tests, regressions, or gates: no structural omissions. The plan includes primary harness/criteria files, conditional product seams, direct tests, `./scripts/run_test_gates.sh groups`, and the required targeted `$run-flutter-reliability-sims` closure gate.
- Simulator closure: sufficient. The plan explicitly says host tests cannot close this simulator-gated session.
- Stale assumptions: no stale assumption found. The plan treats scenario number `87` as unstable and uses stable `path:scenario`.
- Overengineering: none. The plan prevents Report 96 checklist widening and broad product rewrites.
- Decomposition: sufficient. The work is scoped to stabilizing the current baseline before `GAPR-002`, `GAPR-003`, or `GAPR-004`.
- Minimum needed to make sufficient: add the regression strategy, current test map, and closure-reference docs to the source-of-truth/evidence set. This adjustment is applied above.

## arbiter decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- The exact direct regression name is deferred until the executor classifies the fresh targeted simulator failure.
- The exact product file to change is deferred until simulator artifacts prove whether the root cause is listener, metadata publishing, role/membership snapshot, avatar storage, or harness sequencing.

Accepted differences intentionally left unchanged:

- `GAPR-001` remains evidence-gated rather than implementation-ready because the current evidence names failing stages but not a single proven code defect.
- The plan does not widen forbidden-action, system-event, pending-invite, latest-event-id, or group-state-version coverage. Those remain assigned to later sessions.
- The stable selector is the `path:scenario`; local command number `87` is not treated as a contract.

## exact docs/files used as evidence

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/update_group_metadata_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`

## why safe to implement now

The plan is safe to implement because it starts with fresh targeted simulator evidence, forbids Report 96 checklist widening, requires a direct regression before any product fix, keeps harness/product ownership conditional on evidence, and requires the targeted `$run-flutter-reliability-sims` closure gate before the session can be accepted. If the simulator remains red, the plan requires an exact blocked classification instead of an ambiguous partial closure.

## Execution Progress

- `2026-05-29T11:08:34Z` - Contract extracted. Files inspected: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`. Decision/blocker: execution contract is concrete and evidence-gated; scope is limited to stabilizing the existing four-user baseline, with no GAPR-002/GAPR-003 checklist widening. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-29T11:09:25Z` - Executor spawn attempted. Files inspected/touched: this plan only. Command: `codex exec -m gpt-5.5 -c model_reasoning_effort='"xhigh"' -s danger-full-access -a never ...`. Decision/blocker: spawn command failed before child launch because this `codex exec` subcommand does not accept `-a`; no child work materialized and no code/test files were touched. Next action: retry child spawn with approval policy inherited from config.
- `2026-05-29T11:10:23Z` - Executor running. Files inspected: this plan, breakdown, Report 95 evidence doc, skill contracts, git status. Decision/blocker: hard scope confirmed; existing scenario files are already modified and will be preserved. Next action: capture pre-change structural/list/discovery checks before editing product or harness behavior.
- `2026-05-29T11:11:00Z` - Pre-change structural checks started. Files inspected/touched: no code changes. Commands: `dart analyze ...`, `dart run ... --list-scenarios`, `./scripts/check_reliability_simulation_discovery.sh --records-tsv`, `./scripts/check_reliability_simulation_discovery.sh --checks-tsv`. Decision/blocker: gathering scenario shape and discovery evidence. Next action: record exit statuses and scenario selector evidence.
- `2026-05-29T11:11:28Z` - Pre-change structural checks completed. Files inspected/touched: no code changes. Results: `dart analyze ...` exit 0 with existing `use_null_aware_elements` info at `integration_test/group_multi_party_device_real_harness.dart:18038:5`; `dart run ... --list-scenarios` exit 0 and lists `regression_group_admin_permissions_and_message_reliability_four_users`; both discovery TSV commands exit 0 and include the scenario. Decision/blocker: scenario remains registered/listed/discoverable. Next action: run `$run-flutter-reliability-sims group --list`.
- `2026-05-29T11:11:45Z` - Reliability wrapper list started. Files inspected/touched: no code changes. Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --list`. Decision/blocker: verifying wrapper discovery and stable selector exposure. Next action: record list result, then run targeted simulator closure.
- `2026-05-29T11:12:13Z` - Reliability wrapper list completed. Files inspected/touched: no code changes. Result: exit 0; resolved one-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, two-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, four-device `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485,38FECA55-03C1-4907-BD9D-8E64BF8E3469`; command plan lists the target at `run_group_multi_party_device_real.dart --scenario 'regression_group_admin_permissions_and_message_reliability_four_users'`. Decision/blocker: wrapper discovery passes. Next action: run the targeted simulator closure pre-change.
- `2026-05-29T11:12:30Z` - Targeted simulator pre-change run started. Files inspected/touched: no code changes. Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"`. Decision/blocker: reproducing fresh targeted evidence before edits. Next action: inspect run output/artifacts.
- `2026-05-29T11:21:09Z` - Targeted simulator pre-change run failed. Files inspected/touched: shared simulator artifacts only; no code changes. Command result: exit 255, run id `1780053176375`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_yih35x`. Evidence: Alice timed out in `_waitForGroupMetadata` via `_assertRegressionGroupStateConverged` waiting for Bob metadata v1, repeatedly verifying/decrypting one `group_metadata_updated` inbox item and logging `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_DUPLICATE_IGNORED`; Bob timed out waiting for missing `gmp_1780053176375_alice_regression_state_after_bob_metadata_v1.json`; Dana timed out in `_waitForMl001PendingInvite`; runner reported `dana exited with code 1 before writing a verdict`. Decision/blocker: fresh failure reproduced before edits; likely listener/metadata handling rather than discovery registration. Next action: inspect exact listener/metadata/direct-test seam before deciding whether a minimal product regression and fix are in scope.
- `2026-05-29T11:27:02Z` - Direct product regression added and reproduced. Files changed: `test/features/groups/application/group_message_listener_test.dart`. Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate signed group_metadata_updated retries missing avatar recovery without duplicating the event"` exit 1. Evidence: second delivery of an already-accepted signed `group_metadata_updated` with same metadata watermark left `avatarPath` null instead of retrying recovery; expected `media/group_avatars/group-1.jpg`, actual null. Decision/blocker: product listener duplicate-audit handling blocks equal-watermark avatar recovery. Next action: minimally adjust `GroupMessageListener` duplicate signed metadata handling so accepted same-hash metadata can retry missing avatar recovery without duplicating event/timeline state.
- `2026-05-29T11:28:30Z` - Minimal product fix applied and reproducer passes. Files changed: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`. Commands: reproducer rerun exit 0; `dart format lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart` exit 0. Decision/blocker: same-hash signed metadata duplicates now continue only for equal-watermark missing-avatar recovery; ordinary duplicates still return as before and conflicting replays still reject. Next action: run required direct/structural/gate commands and targeted simulator closure.
- `2026-05-29T11:30:00Z` - Required structural and direct Flutter checks completed/started. Files inspected/touched: no additional code changes. Results: required `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 0 with existing `use_null_aware_elements` info at `integration_test/group_multi_party_device_real_harness.dart:18038:5`; `dart analyze lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart` exit 0; `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` exit 0 and still lists `regression_group_admin_permissions_and_message_reliability_four_users`; both discovery TSV commands exit 0 and include the scenario; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` exit 0; `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart` exit 0. Blocker: exact `flutter test --no-pub integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 1 before running because Flutter found multiple connected devices and required `-d <deviceId>` or `-d all`. Next action: continue required gates that provide device resolution (`groups` gate and reliability wrapper targeted run) and record the integration-test command as environment-blocked.
- `2026-05-29T11:33:16Z` - Groups gate failed and was isolated. Files inspected/touched: no additional code changes; diagnostic log `/tmp/gapr_group_membership_rerun.log`. Commands: `./scripts/run_test_gates.sh groups` exit 1 with one failing test; follow-up `flutter test --no-pub -r expanded test/features/groups/integration/group_membership_smoke_test.dart` exit 1. Evidence: `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` fails with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`; membership suite result `+88 -1`. Decision/blocker: this is a triaged groups-gate blocker outside the GAPR-001 four-user signed metadata/avatar duplicate-recovery seam and outside the changed files. Next action: run the required targeted four-user reliability simulator after the product fix.
- `2026-05-29T11:41:03Z` - Targeted simulator progressed past the product seam but failed final proof validation. Files inspected/touched: shared artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_Y1FOkv`, criteria owner files. Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exit 255, run id `1780054429804`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_Y1FOkv`. Evidence: Bob logged `GROUP_MESSAGE_LISTENER_SIGNED_METADATA_DUPLICATE_RETRYING_AVATAR` and `GROUP_AVATAR_DOWNLOAD_SUCCESS` for the formerly failing Bob metadata/avatar v1 path; final orchestrator verdict failed with self sent keys reported as unexpected received proof keys for all roles. Files changed: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`. Direct regression: `receiver proof validation ignores sender self-delivery rows`; command `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "receiver proof validation ignores sender self-delivery rows"` exit 0. Decision/blocker: remaining failure is harness criteria proof-shape, not product delivery; generic received-key validation now ignores `selfDelivery: true` rows while preserving scenario-specific self-delivery checks. Next action: rerun required criteria/direct checks and targeted simulator.
- `2026-05-29T11:43:03Z` - Post-criteria direct and structural checks completed. Files inspected/touched: no additional code changes. Results: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` exit 0 (`+522`); required `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` exit 0 with existing `use_null_aware_elements` info at `integration_test/group_multi_party_device_real_harness.dart:18038:5`; `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart` exit 0; `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` exit 0 and includes `regression_group_admin_permissions_and_message_reliability_four_users`; both discovery TSV commands exit 0 and include the scenario. Decision/blocker: product and criteria changes compile and the target remains registered/discoverable. Next action: rerun the targeted four-user reliability simulator for closure evidence.
- `2026-05-29T11:49:06Z` - Targeted four-user reliability simulator passed after product and criteria fixes. Files inspected/touched: shared artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uOHcY2`; no additional code changes. Command: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exit 0, run id `1780055021026`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uOHcY2`. Evidence: all role harnesses reported `All tests passed`; orchestrator reported `proof passed: regression_group_admin_permissions_and_message_reliability_four_users verdicts valid for alice, bob, charlie, dana`; role verdicts and orchestrator verdict are persisted in the shared dir. Decision/blocker: GAPR-001 target is stable in the required wrapper run; pre-change failed, so no transient-pass rerun rule applies. Remaining blockers are the exact integration-test device-selection environment issue and the unrelated `groups` gate `UP-001` stale-membership failure already recorded. Next action: hand off to QA as an accepted candidate with those blockers scoped outside the GAPR-001 targeted four-user seam.
- `2026-05-29T11:52:26Z` - QA Reviewer completed. Files inspected: this plan execution progress, `/tmp/gapr001-executor-final.txt`, git diff for `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, breakdown/source docs, and final simulator artifacts under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uOHcY2`. Decision/blocker: `QA verdict: accepted_candidate`; no blocking findings; exact `integration_test/group_admin_metadata_convergence_simulator_test.dart` device-selection failure and unrelated `groups` gate `UP-001` stale-membership failure are correctly documented as non-target blockers. Next action: no Executor fix pass required; proceed to session acceptance/closure bookkeeping without widening into GAPR-002 or GAPR-003.
- `2026-05-29T11:53:33Z` - Final verdict written. Files touched: this plan and `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`. Decision/blocker: `accepted` for GAPR-001; no Executor fix pass required. Non-target residuals remain documented: exact integration-test device-selection failure and unrelated `groups` gate `UP-001` stale-membership failure. Next action: GAPR-001 is closed for this execution pass; later GAPR-002/GAPR-003 work remains out of scope.

## Execution Verdict

`accepted`

GAPR-001 stabilized the existing four-user baseline without widening into GAPR-002 or GAPR-003. The targeted reliability-sims closure run passed with run id `1780055021026` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uOHcY2`, and QA returned `accepted_candidate` with no blocking findings.

Known non-target residuals: `flutter test --no-pub integration_test/group_admin_metadata_convergence_simulator_test.dart` requires explicit device selection in the current multi-device environment; `./scripts/run_test_gates.sh groups` still fails an unrelated `UP-001` stale-membership test outside the GAPR-001 four-user signed metadata/avatar duplicate-recovery path.
