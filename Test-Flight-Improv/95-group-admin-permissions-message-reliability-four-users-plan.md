Status: blocked - required targeted simulator closure exposes product regression

# 95 - Group Admin Permissions And Four-User Message Reliability

## Planning Progress

- 2026-05-29T00:00:00Z - Evidence Collector started. Files inspected: `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_reliability_simulations.sh`, `scripts/check_reliability_simulation_discovery.sh`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `integration_test/group_admin_metadata_convergence_simulator_test.dart`. Decision/blocker: selected repo-local plan path and confirmed this is simulator-gated group reliability work. Next action: collect exact seams and existing scenario coverage.
- 2026-05-29T00:05:00Z - Evidence Collector completed locally after spawned explorer timeout. Files inspected: same files plus local reliability dry-run output. Decision/blocker: existing group multi-party runner already supports `path:scenario` selection and four role scenarios; no blocker. Next action: Planner draft.
- 2026-05-29T00:08:00Z - Planner completed. Files inspected: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `scripts/run_reliability_simulations.sh`. Decision/blocker: add one new scenario in the existing group multi-party simulator harness. Next action: Reviewer pass.
- 2026-05-29T00:10:00Z - Reviewer completed. Files inspected: `Test-Flight-Improv/test-gate-definitions.md`, reliability dry-run output. Decision/blocker: plan must include `$run-flutter-reliability-sims` closure for the new scenario and direct discovery/list checks. Next action: Arbiter pass.
- 2026-05-29T00:12:00Z - Arbiter completed. Files inspected: plan draft and evidence set. Decision/blocker: no structural blocker; execution-ready with simulator-gated closure. Next action: execute via `$implementation-execution-qa-orchestrator`.

## Execution Progress

- 2026-05-29T00:13:00Z - Contract extracted. Files inspected/touched: `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`. Command currently running: none. Decision/blocker: exact scope, tests, gates, done criteria, and scope guard are present. Next action: spawn Executor.
- 2026-05-29T08:10:17Z - Executor contract extracted. Files inspected/touched: `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`. Command currently running: none. Decision/blocker: add only `regression_group_admin_permissions_and_message_reliability_four_users` to the existing group multi-party simulator harness, runner, and criteria; add regression first; run structural discovery/analyze, host tests, `groups` gate, and targeted `$run-flutter-reliability-sims` closure as available; product code stays out of scope unless the new regression exposes a concrete defect. Next action: inspect owner files and wire the scenario.
- 2026-05-29T08:14:04Z - Owner files inspected. Files inspected/touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`. Command currently running: none. Decision/blocker: existing prompt/admin helpers cover invite acceptance, signed metadata/role changes, avatar upload/regrant, member add/remove payloads, and proof-message waits; new work can stay scenario-scoped. Next action: edit harness, runner, and criteria.
- 2026-05-29T08:55:00Z - Executor implementation completed. Files inspected/touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`. Command currently running: none. Decision/blocker: new four-role scenario, contact graph, convergence/avatar/message/rejection proof helpers, criteria validator, and runner registration are implemented. Next action: run structural checks, host gates, and targeted simulator closure.
- 2026-05-29T09:05:00Z - Structural and host checks completed. Files inspected/touched: same implementation files. Command currently running: none. Decision/blocker: `dart format` passed; `dart analyze` passed with one existing style info in the changed harness (`use_null_aware_elements`); `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` passed; `./scripts/check_reliability_simulation_discovery.sh --records-tsv` passed; `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` passed; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed; `flutter test integration_test/group_admin_metadata_convergence_simulator_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469` passed. Next action: run required named and simulator gates.
- 2026-05-29T09:10:00Z - Named host gate triaged. Files inspected/touched: no new files. Command currently running: none. Decision/blocker: `./scripts/run_test_gates.sh groups` failed in `test/features/groups/integration/group_membership_smoke_test.dart` on `ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending`; an isolated rerun of that exact test passed, so this is recorded as unrelated/flaky and not the blocker for this session. Next action: run `$run-flutter-reliability-sims` discovery and targeted closure.
- 2026-05-29T09:14:00Z - `$run-flutter-reliability-sims` discovery completed. Files inspected/touched: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`. Command currently running: none. Decision/blocker: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` passed and lists `integration_test/scripts/run_group_multi_party_device_real.dart --scenario regression_group_admin_permissions_and_message_reliability_four_users` as scenario 87. Next action: run the required targeted simulator closure.
- 2026-05-29T09:20:00Z - QA Reviewer completed. Files inspected/touched: plan, harness, criteria, runner. Command currently running: none. Decision/blocker: reviewer found no missing harness assertion blocking the regression; scenario is registered/discoverable, and validator requires final state, rejected actions, state convergence, avatar byte proof, and self-delivery proof. QA verdict remains blocked because the required targeted simulator closure fails. Next action: record exact simulator failure evidence.
- 2026-05-29T09:22:00Z - Required targeted simulator closure failed. Files inspected/touched: same implementation files. Command currently running: none. Decision/blocker: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` exited 255 on run id `1780045992012`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_LNyrkV`. Bob timed out in `_waitForGroupMetadata` at stage `after_charlie_metadata_v2`; Alice and Charlie wrote their state proofs, Bob did not. This is triaged as a product/reliability regression in promoted-admin metadata/avatar convergence, not a missing harness assertion. A prior targeted attempt also exposed Dana failing to converge at `after_alice_avatar_v3`. Next action: product fix required before this plan can be accepted closed.

## Final Execution Status

Implemented, registered, and validated structurally, but not accepted closed.

The new simulator regression is available to `$run-flutter-reliability-sims group` and fails on the required targeted run because active members do not converge after admin-role and avatar metadata changes. The current final failure is Bob missing Charlie's `image-v2`/metadata state at `after_charlie_metadata_v2`; an earlier targeted run also showed Dana missing Alice's later `image-v3` state at `after_alice_avatar_v3`.

QA Reviewer classification: blocked by product/test gate failure. No harness-coverage blocker remains.

## Real Scope

Add one required four-user group reliability regression named `regression_group_admin_permissions_and_message_reliability_four_users` to the existing group multi-party simulator infrastructure.

In scope:

- Register the new scenario in `integration_test/scripts/group_multi_party_device_criteria.dart`.
- Add the scenario to `integration_test/scripts/run_group_multi_party_device_real.dart` scenario parsing/listing.
- Implement the scenario in `integration_test/group_multi_party_device_real_harness.dart` using the existing four-role harness roles `alice`, `bob`, `charlie`, and `dana`.
- Add or extend helper methods inside the same harness for group state convergence, avatar byte visibility, full active-member message matrix, and rejected action proof.
- Make the scenario discoverable through `scripts/run_reliability_simulations.sh` and therefore through `$run-flutter-reliability-sims`.
- If the new regression exposes a concrete product defect in group admin permissions, metadata/avatar propagation, invite authorization, removal enforcement, or group message fanout, fix only that defect and add the narrow host test needed to pin it.

Out of scope:

- UI redesign or broad Group Info refactors.
- New product features or changed admin policy.
- Rewriting the existing multi-party harness architecture.
- Full reliability-sim `group` sweep unless the targeted scenario passes and the executor has available device/runtime budget.

## Closure Bar

The session is good enough when:

- `regression_group_admin_permissions_and_message_reliability_four_users` appears in `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios`.
- The new scenario appears in the `group` reliability dry-run produced by `$run-flutter-reliability-sims`.
- The scenario validates all active members converge after every group-control operation before the next operation proceeds.
- The scenario verifies admin and non-admin behavior across all four roles, including demoted-admin rejections, non-friend invite rejection, removed-member send/receive exclusion, avatar metadata plus file bytes, and full active-member message delivery after major changes.
- The targeted simulator command passes on four resolved simulator/device IDs, or any failure is triaged as product, harness, test, pre-existing, flaky, unrelated-but-required, or environment/tooling.

Host tests and analyzer checks are required for compile and discovery shape, but host tests alone do not close this session.

## Source Of Truth

- User issue text in this prompt is the scenario source of truth.
- Current code wins on implementation details.
- `Test-Flight-Improv/test-gate-definitions.md` is the named gate source of truth.
- `scripts/run_reliability_simulations.sh` and `$run-flutter-reliability-sims` define simulator discovery and execution behavior.
- `integration_test/scripts/group_multi_party_device_criteria.dart` is the source of truth for scenario registration, role count, verdict validation, and exact message proof expectations.
- `integration_test/group_multi_party_device_real_harness.dart` is the source of truth for app-instance role choreography.

## Session Classification

blocked/test_or_gate_failure

This is simulator-gated Flutter/mobile group reliability work. The regression has been implemented in the existing four-role group multi-party harness, but the required targeted simulator closure exposes a group metadata/avatar convergence defect that must be fixed before the session can close accepted.

## Exact Problem Statement

The repo has separate coverage for promoted-admin metadata, demotion enforcement, non-friend member delivery, and membership churn, but it does not have one required end-to-end four-user regression that exercises the full admin-permission lifecycle while verifying group state convergence and message fanout after every major group-control operation.

User-visible behavior that must improve: group admins and members must see consistent group details, roles, membership, avatar bytes, and messages after promotion, demotion, invite, metadata, image, and removal operations across four online app instances.

Must stay unchanged: an admin may invite only their own friends; accepted group members do not need mutual friendship to chat; non-admins and removed members remain unable to mutate group state or send active group messages.

## Files And Repos To Inspect Next

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `scripts/run_reliability_simulations.sh`
- `scripts/check_reliability_simulation_discovery.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- If product failure appears: `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/update_group_member_role_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, and their existing direct tests.

## Existing Tests Covering This Area

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart` covers promoted-admin metadata/photo, promoted-admin invite, C-to-creator fanout, Scenario 4 demotion enforcement, and avatar snapshot behavior.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` wraps the host convergence journeys for simulator execution.
- `integration_test/scripts/run_group_multi_party_device_real.dart` already lists and runs multi-party scenarios and supports `--scenario <id>`.
- `integration_test/scripts/group_multi_party_device_criteria.dart` already validates role requirements, exact sent/received proof counts, duplicate receive prevention, and scenario-specific proof fields.
- Existing four-role scenarios include `private_admin_demotion_enforcement`, `private_non_friend_member_delivery`, `private_admin_role_transfer_delivery`, and many `gm*` scenarios, but none combines the exact 15-phase four-user admin permission and message reliability journey requested here.

## Regression/Tests To Add First

Add the new scenario/test first:

- Scenario id and test name: `regression_group_admin_permissions_and_message_reliability_four_users`.
- Roles: `alice=user-a`, `bob=user-b`, `charlie=user-c`, `dana=user-d`.
- Initial contact graph:
  - `alice <-> bob`
  - `bob <-> charlie`
  - `bob <-> dana`
  - `charlie <-> dana`
  - no `alice <-> charlie`
  - no `alice <-> dana`

Required helper behavior:

- `assertGroupStateConverged`: compare name, description, avatar blob/media id, avatar mime/path, active members, admins, removed members where locally represented, pending invite absence/presence where meaningful, latest membership/metadata event watermarks or state hash, and key epoch.
- `assertGroupImageVisible`: wait for avatar metadata, resolve the canonical avatar path, assert the file exists and has non-empty supported image bytes, and compare SHA-256 with the expected upload bytes.
- `assertFullMessageMatrix`: each active role sends a unique proof message and every active peer receives it exactly once; excluded/removed peers do not receive post-removal proof messages.
- `assertRejectedWithoutStateChange`: capture pre-action group state hash and local values, run the forbidden action, assert rejected/blocked outcome, assert no accepted local success, assert no remote state mutation, and assert the post-action hash is unchanged on all active peers.

## Step-By-Step Implementation Plan

1. Register the scenario in `group_multi_party_device_criteria.dart`.
   - Add a `GroupMultiPartyScenarioRequirement` with roles `alice`, `bob`, `charlie`, `dana`.
   - Add it to `_scenarioRequirements`, `_scenariosToRun` in the runner, and the runner usage string.
   - Add expected proof message keys covering every full matrix phase and post-removal exclusion.
   - Add a scenario-specific validator that checks the final state and rejected-action proof map.

2. Add initial-contact setup for the new scenario in `group_multi_party_device_real_harness.dart`.
   - Prefer a new `_addRegressionAdminPermissionsInitialContacts` helper instead of changing generic `_addPeerContacts`.
   - Use the exact contact graph from the user issue.

3. Add focused harness helpers in `group_multi_party_device_real_harness.dart`.
   - Use existing `buildGroupTransitionStateHash`, `_memberPeerIds`, `_keyEpoch`, `_waitForGroupMetadata`, `_waitForMemberRole`, `_waitForMemberInclusion`, `_waitForMemberExclusion`, `_waitForReceivedProofMessage`, `_sendProofMessage`, `_uploadPromptGroupAvatar`, `_regrantPromptGroupAvatarForMembers`, `_publishGroupMetadataUpdate`, `_updateMemberRoleAndPublish`, `_publishMembersAddedSystemPayload`, `_prepareMemberRemovedSystemPayload`, and `downloadGroupAvatar` behavior where possible.
   - Add only narrow helpers needed for the requested scenario, keeping names scenario-scoped if they are not reusable.

4. Implement role choreography in the harness.
   - Alice creates the group with Bob; Bob accepts.
   - Bob's pre-promotion forbidden mutations fail.
   - Alice promotes Bob; Bob changes name, description, image; Alice receives all changes.
   - Bob invites Charlie; Charlie accepts latest snapshot and image.
   - Charlie's non-admin forbidden mutations fail.
   - Alice's invite to Dana fails because Alice and Dana are not friends.
   - Alice promotes Charlie; Charlie changes name, description, image.
   - Alice demotes Bob; Bob remains member and loses admin rights.
   - Bob's demoted-admin forbidden mutations fail.
   - Charlie invites Dana; Dana accepts latest snapshot and image.
   - Bob still cannot promote/demote/remove after Dana joins.
   - Alice changes image after role churn.
   - Charlie removes Dana; Dana cannot send, and Dana receives no new post-removal messages.
   - Final state is `name=test me v2`, `description=do you see me v2?`, image v3, active members A/B/C, removed D, admins A/C.

5. Write verdict proof data.
   - Every role must write one scenario proof object.
   - Active roles must include final metadata, final roles, final active member peer IDs, key epoch, state hash, avatar SHA-256, forbidden action outcomes, full message matrix phase keys, and post-removal exclusion.
   - Dana's proof must show accepted before removal, removed locally/no active access after removal, send rejected after removal, and no post-removal messages received.

6. Run the direct compile/discovery checks.
   - Fix test/harness compile errors without weakening assertions.

7. Run the targeted simulator closure with `$run-flutter-reliability-sims`.
   - If it fails, triage first. Product-code fixes are allowed only for failures in the exact paths described by this plan.

## Risks And Edge Cases

- Multi-party simulator runtime is long and can fail because of simulator/device availability.
- Avatar metadata can converge before bytes are downloaded; byte hash proof must wait for the file.
- A demoted admin can still have stale local state; forbidden action checks must assert both local rejection and remote no-op.
- Message delivery must be based on active group membership, not friendship or inviter relationship.
- Removing Dana must exclude new messages from both live topic and offline replay.
- State hash comparisons must avoid transient false negatives by waiting for known control-event convergence before comparing.

## Exact Tests And Gates To Run

Direct structural checks:

```bash
dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios
./scripts/check_reliability_simulation_discovery.sh --records-tsv
./scripts/check_reliability_simulation_discovery.sh --checks-tsv
```

Direct host/simulator-adjacent tests:

```bash
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart
flutter test integration_test/group_admin_metadata_convergence_simulator_test.dart
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Required simulator closure gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"
```

If the targeted simulator closure passes and runtime/device budget allows, run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
```

The final closure remains the targeted `--only` scenario. A full group reliability sweep is optional for this session unless product code changes widen the blast radius beyond the scenario.

## Known-Failure Interpretation

- Pre-existing red items in `Test-Flight-Improv/test-gate-definitions.md` or unrelated simulator/device failures must not be misclassified as this session's regression unless the changed files clearly caused or widened them.
- Failure to resolve four distinct simulator IDs is an environment blocker, not a code failure.
- A new failure inside `regression_group_admin_permissions_and_message_reliability_four_users` is blocking until triaged as harness/test/product/environment and either fixed or documented with exact evidence.

## Done Criteria

- Plan has `Status: execution-ready`.
- New scenario is registered, listed, discovered, and selectable by `path:scenario`.
- New scenario is available through `$run-flutter-reliability-sims group`.
- Direct structural checks pass.
- Required host/simulator-adjacent tests and `./scripts/run_test_gates.sh groups` pass or are triaged according to known-failure policy.
- Required targeted simulator closure gate passes, or the session is reported blocked with exact failing command, exit code, and root cause.
- QA Reviewer finds no blocking issues.

## Scope Guard

Do not:

- Broaden into unrelated group features.
- Loosen admin authorization, friend-invite, removed-member, or message fanout assertions to make the test pass.
- Replace byte/avatar proof with metadata-only proof.
- Use one local actor's state as convergence evidence.
- Remove or weaken existing group reliability scenarios.
- Skip `$run-flutter-reliability-sims` targeted closure if devices are available.

## Accepted Differences / Intentionally Out Of Scope

- This scenario is an app-peer simulator regression, not a UI-tap regression. It may use app harness APIs instead of manually tapping Group Info controls, as long as it exercises the same use cases and verifies every active simulator.
- The scenario may assert hashes, epochs, member roles, and proof messages through repositories/verdict files rather than visible UI text, except system timeline events that already exist as persisted group messages.
- Full group reliability sweep is intentionally optional; the new targeted scenario is the required closure because the group scope currently contains more than 100 simulator commands.

## Dependency Impact

This scenario becomes a required regression for future group messaging reliability work, especially changes to admin role updates, metadata/avatar propagation, invite acceptance, membership removal, and group message fanout. If this scenario cannot be added or cannot be made selectable through `$run-flutter-reliability-sims`, downstream group reliability claims should not cite this session as closed.

## Reviewer Findings

- Sufficient with adjustments: the plan correctly targets the existing group multi-party runner and requires simulator closure.
- Missing item fixed before arbiter: direct discovery/list checks and `$run-flutter-reliability-sims group --only <path:scenario>` were added to the exact gates.
- No overengineering finding: one new scenario in existing harness is narrower than creating a parallel E2E framework.

## Arbiter Decision

No structural blockers remain.

Incremental details intentionally deferred:

- Exact helper names may change during implementation if a clearer local naming pattern emerges.
- Optional full group simulator sweep is deferred unless product-code changes widen scope.

Accepted differences intentionally left unchanged:

- Repo uses `integration_test/scripts/run_group_multi_party_device_real.dart` rather than a `tests/group/e2e_group_admin_permissions_reliability_test.*` path. The new regression must live in that existing simulator-discovery path so `$run-flutter-reliability-sims` can run it.
