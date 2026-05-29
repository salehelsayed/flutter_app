# GAPR-002 - Expand Forbidden Admin-Action Rejection Matrix

Status: accepted

## Execution Progress

- `2026-05-29 14:38:06 CEST` - Closure audit accepted GAPR-002 evidence from this plan and `/tmp/gapr-002-executor-result.md`. Verified the plan top status and breakdown ledger already record `accepted`; no breakdown edit is needed. Accepted evidence remains scoped to the forbidden admin-action rejection matrix, direct analyzer/criteria/discovery checks, and targeted four-device simulator run id `1780057317153`. The named `groups` gate remains non-green only because of the known non-target `UP-001` stale-membership residual at `lib/features/groups/application/add_group_member_use_case.dart:281`. Decision/blocker: GAPR-002 closure is accepted with the explicit non-target residual preserved; no GAPR-003 system-event/latest-event/version convergence proof or final program verdict is claimed.
- `2026-05-29 14:36:17 CEST` - Controller final verdict recorded after isolated QA Reviewer pass. QA verdict: `ACCEPTED`, with no blocking findings. Evidence accepted: direct analyzer commands passed, criteria test passed with 528 tests, scenario listing/discovery/list checks passed, targeted four-device simulator passed with run id `1780057317153`, and `./scripts/run_test_gates.sh groups` failure was classified as the known non-target `UP-001` stale-membership residual at `lib/features/groups/application/add_group_member_use_case.dart:281`. Decision/blocker: GAPR-002 accepted; no fix loop required. Next action: update breakdown ledger to accepted.
- `2026-05-29 14:31:06 CEST` - Executor completion checkpoint. Files touched in this pass: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Files intentionally not touched: production group application code and the breakdown ledger. Commands run for closure: `git status --short` and scoped `git diff --stat` for touched files. Decision/blocker: GAPR-002 implementation and direct closure are complete; residual gate failure is the known non-target `UP-001` stale-membership issue. Next action: hand off to QA Reviewer/controller without claiming acceptance.
- `2026-05-29 14:30:53 CEST` - Executor ran the named groups gate and diagnostic isolation. Command: `./scripts/run_test_gates.sh groups` exit 1 after `+311 -1`; diagnostic command `flutter test --no-pub -r expanded test/features/groups/integration/group_membership_smoke_test.dart > /tmp/gapr002_group_membership_rerun.log 2>&1` exit 1. Evidence: `/tmp/gapr002_group_membership_rerun.log` confirms the unchanged non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` failure with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`; membership suite ended `+88 -1`. Decision/blocker: classified as the already documented GAPR-001 residual outside this session's forbidden admin-action rejection matrix; no GAPR-002 production fix taken. Next action: final worktree and completion checkpoint.
- `2026-05-29 14:28:08 CEST` - Executor completed direct checks and targeted simulator closure before the named gate. Commands run: `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart` (exit 0 after lint cleanup), `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (exit 0), `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` (exit 0; 528 tests passed), `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` (exit 0; target listed), `./scripts/check_reliability_simulation_discovery.sh --records-tsv` (exit 0), `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` (exit 0), `run_with_devices.sh group --list` (exit 0), and `run_with_devices.sh group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"` (exit 0; run id `1780057317153`; verdicts valid for alice, bob, charlie, dana; logs in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_YRp76n`). Decision/blocker: no product fix needed; expanded forbidden-action proof passed in the real harness. Next action: run `./scripts/run_test_gates.sh groups`.
- `2026-05-29 14:19:35 CEST` - Executor implemented GAPR-002 harness/criteria expansion. Files touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and this plan. Commands run: `dart format integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (exit 0). Decision/blocker: no production code touched; expansion records action-specific forbidden outcomes and Dana no-invite evidence. Next action: run direct analyzer and criteria tests.
- `2026-05-29 14:08:53 CEST` - Executor started locally under isolated Executor-only contract. Files inspected: plan file, implementation-execution workflow skill, run-flutter-reliability-sims skill, `git status --short`, `GAPR-001` status, and current diffs for harness/criteria/criteria tests plus GAPR-001 listener changes. Decision/blocker: `GAPR-001` is accepted and worktree is dirty with expected prior changes; proceed without reverting unrelated work. Next action: inspect current harness/criteria proof seams and add GAPR-002 matrix regressions.
- `2026-05-29 14:07:10 CEST` - Controller contract extraction completed. Files inspected: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, and `git status --short`. Decision/blocker: execution contract is explicit and `GAPR-001` is accepted; spawned Executor will run with `model: gpt-5.5` and `reasoning_effort: xhigh`. Next action: spawn Executor for the forbidden admin-action rejection matrix expansion only.

## Planning Progress

- `2026-05-29 14:17:30 CEST` - Evidence Collector completed; Planner started. Files inspected since last update: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, group admin application use cases and tests. Decision/blocker: current scenario has partial combined rejection proof; session can plan a harness/criteria proof expansion with conditional direct product tests only if a forbidden action is not rejected. Next action: draft the execution-ready plan with checklist coverage mapping.
- `2026-05-29 13:58:10 CEST` - Evidence Collector started. Inspected `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md` and `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`; confirmed session `GAPR-002`, required plan path, dependency on accepted `GAPR-001`, and doc-scoped planning-only request. Next action: inspect direct harness, criteria, runner, and gate evidence before drafting.
- `2026-05-29 14:03:00 CEST` - Local planning fallback completed. Files inspected: current GAPR-001 accepted plan, `integration_test/group_multi_party_device_real_harness.dart` rejection helpers and Alice/Bob/Charlie/Dana choreography, `integration_test/scripts/group_multi_party_device_criteria.dart` validator, `test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: plan is execution-ready and scoped to independent forbidden-action proof expansion. Next action: execute with the downstream execution/QA workflow.

## Real Scope

Expand the existing four-user simulator scenario so every Report 96 forbidden admin option has independent observable rejection evidence for the relevant actor state.

In scope:

- Add independent rejection attempts and proof fields for:
  - non-admin Bob before promotion: change name, change description, change image, promote himself, demote Alice, remove Alice, add/invite Charlie
  - non-admin Charlie before promotion: change name, change description, change image, promote himself, demote Bob, remove Bob, invite Dana
  - demoted Bob before Dana joins: change name, change description, change image, invite Dana, promote Dana, demote Charlie, remove Dana where the target/action is meaningful at that stage
  - demoted Bob after Dana joins: forbidden admin attempts against valid current-member targets, especially promote Dana, demote Charlie, and remove Dana
  - Alice inviting Dana while Alice and Dana are not friends: no local mutation, no remote mutation, and Dana gets no invite
  - Dana after removal: admin actions fail in addition to send rejection and no post-removal plaintext delivery
- Make each rejected action record:
  - blocked/rejected outcome, never `accepted`
  - local state hash unchanged
  - active remote peer state unchanged after the scenario convergence checkpoint
  - no user-visible fake success field in the proof payload, using existing harness evidence surfaces where possible
- Tighten `integration_test/scripts/group_multi_party_device_criteria.dart` so the scenario-specific validator requires every new independent proof field and rejects the older combined-only proof shape.
- Add focused criteria tests in `test/integration/group_multi_party_device_criteria_test.dart` proving the validator rejects missing or accepted forbidden-action fields.
- Add narrow product tests only if execution proves a named forbidden action is actually accepted by product code.

Out of scope:

- GAPR-003 system-event text, latest event id, pending-invite convergence fields, or group state version proof.
- GAPR-004 final program closure/docs reconciliation.
- New admin policy, new scenario identity, new simulator framework, UI redesign, or transport/libp2p changes.
- Reworking the GAPR-001 duplicate metadata/avatar recovery fix except to preserve compatibility.

## Closure Bar

This session is accepted only when:

- `regression_group_admin_permissions_and_message_reliability_four_users` still passes the GAPR-001 baseline and now emits independent forbidden-action proof for all GAPR-002 actor/action states.
- The criteria validator rejects proofs missing the expanded forbidden-action matrix.
- Rejected-action proof proves blocked/rejected outcome, local unchanged hash, and active remote no-op through later convergence checkpoints or explicit peer snapshots.
- Dana after removal has explicit admin-action rejection proof, not just send rejection and message-exclusion proof.
- Alice's non-friend Dana invite proof includes Dana no-invite evidence.
- Direct criteria tests and targeted harness/criteria checks pass.
- The targeted `$run-flutter-reliability-sims` scenario passes after the proof expansion, or the session is truthfully blocked with exact command, run id, shared dir, failing role/stage, and first missing or accepted forbidden action.

Host/criteria tests alone cannot close this simulator-proof session.

## Source Of Truth

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md` is the checklist source.
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md` is the active session contract.
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md` records the accepted stable baseline and known non-target residuals.
- `integration_test/group_multi_party_device_real_harness.dart` owns the role choreography and proof payloads.
- `integration_test/scripts/group_multi_party_device_criteria.dart` owns verdict validation.
- `test/integration/group_multi_party_device_criteria_test.dart` is the direct regression home for criteria proof-shape validation.
- `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/_current-test-map.md` define the relevant groups gate and manual simulator classification.

## Current Evidence

Current harness coverage already includes:

- Bob before promotion has combined metadata and member-add rejections.
- Charlie before promotion has non-admin rejections.
- Alice non-friend Dana invite is attempted and state-unchanged is recorded.
- Demoted Bob has combined metadata and member-add rejections before Dana joins.
- Bob after Dana joins has role-update and remove rejections.
- Dana after removal has send rejection and post-removal plaintext exclusion.

Current gaps for this session:

- Metadata rejection is not split into name, description, and image attempts.
- Bob before promotion lacks independent promote-self, demote-Alice, and remove-Alice proof.
- Charlie before promotion lacks independent promote-self, demote-Bob, remove-Bob, and invite-Dana proof if not already individually named.
- Demoted Bob lacks independent image, promote-Dana, demote-Charlie, and every valid-current-member post-Dana forbidden variant.
- Dana after removal lacks admin-action attempts.
- Criteria accepts broad combined booleans such as `bobPrePromotionStateUnchanged` and does not yet require every independent field.

## Implementation Plan

1. Inspect and preserve the GAPR-001 changes.
   - Confirm `Status: accepted` in the GAPR-001 plan.
   - Inspect current diffs in `GroupMessageListener`, listener tests, criteria, and criteria tests before editing.
   - Do not revert existing uncommitted changes.

2. Add scenario-scoped rejected-action helpers if needed.
   - Prefer extending `_regressionAssertRejectedWithoutStateChange` with optional proof labels and remote snapshot support rather than creating unrelated generic helpers.
   - Add action-specific helpers only when they make the choreography clearer:
     - metadata name-only attempt
     - metadata description-only attempt
     - metadata image-only attempt
     - role update to admin/writer for a named target
     - remove named target
     - add/invite named target
   - Keep helper names scoped to regression admin permissions.

3. Expand Bob pre-promotion proof.
   - Replace/augment the current combined metadata/member-add proof with independent fields:
     - `bobPrePromotionNameAttemptOutcome`
     - `bobPrePromotionDescriptionAttemptOutcome`
     - `bobPrePromotionImageAttemptOutcome`
     - `bobPrePromotionAddCharlieAttemptOutcome`
     - `bobPrePromotionPromoteSelfAttemptOutcome`
     - `bobPrePromotionDemoteAliceAttemptOutcome`
     - `bobPrePromotionRemoveAliceAttemptOutcome`
   - Add matching `...StateUnchanged` booleans for each action, or a structured map that criteria can validate per action.

4. Expand Charlie non-admin proof.
   - Add independent fields:
     - `charlieNonAdminNameAttemptOutcome`
     - `charlieNonAdminDescriptionAttemptOutcome`
     - `charlieNonAdminImageAttemptOutcome`
     - `charlieNonAdminInviteDanaAttemptOutcome`
     - `charlieNonAdminPromoteSelfAttemptOutcome`
     - `charlieNonAdminDemoteBobAttemptOutcome`
     - `charlieNonAdminRemoveBobAttemptOutcome`
   - Preserve the existing convergence checkpoint after Charlie's rejected actions.

5. Expand Alice non-friend Dana invite proof.
   - Keep `aliceDanaInviteAttemptOutcome` and `aliceDanaInviteStateUnchanged`.
   - Add explicit no-invite evidence for Dana, for example `aliceDanaInviteNoPendingInviteForDana` or an equivalent proof field sourced from Dana's pending invite repo/checkpoint.
   - Criteria must fail if the attempt is blocked locally but Dana still sees a pending invite.

6. Expand demoted Bob proof before Dana joins.
   - Add independent fields:
     - `bobDemotedNameAttemptOutcome`
     - `bobDemotedDescriptionAttemptOutcome`
     - `bobDemotedImageAttemptOutcome`
     - `bobDemotedInviteDanaAttemptOutcome`
     - `bobDemotedPromoteDanaAttemptOutcome`
     - `bobDemotedDemoteCharlieAttemptOutcome`
     - `bobDemotedRemoveDanaAttemptOutcome` if the harness can attempt it meaningfully before Dana joins; otherwise record `not_applicable_before_join` and cover the valid-current-member remove in the post-Dana stage.
   - Do not weaken the existing `after_bob_demoted_rejections` convergence checkpoint.

7. Expand demoted Bob proof after Dana joins.
   - Add independent fields for valid current-member targets:
     - `bobPostDanaPromoteDanaAttemptOutcome`
     - `bobPostDanaDemoteCharlieAttemptOutcome`
     - `bobPostDanaRemoveDanaAttemptOutcome`
     - optional repeated metadata/image/invite checks only if needed to satisfy the source doc's "post-Dana forbidden admin variants"
   - Keep `after_bob_post_dana_rejections` convergence.

8. Add Dana post-removal admin-action proof.
   - After Dana is removed and local no-active-access is proven, attempt admin actions through the safest available harness APIs:
     - metadata/name or image update
     - role update/promote self or another known member
     - remove member
     - add/invite member if contacts are available
   - Record explicit `danaPostRemovalAdminAction...Outcome` and state/no-access unchanged fields.
   - Preserve existing send rejection and no-post-removal-plaintext proof.

9. Tighten scenario criteria.
   - In `_validateRegressionGroupAdminPermissionsFourUsersProof`, require all action-specific outcome fields and state-unchanged fields by role.
   - Treat `accepted`, missing, empty, and `not_attempted` as failures unless a field is explicitly documented as `not_applicable_before_join`.
   - Keep final-state, message-matrix, self-delivery, avatar, role, member, and removed-member checks intact.
   - Add criteria tests proving:
     - valid expanded proof passes
     - missing Bob pre-promotion independent field fails
     - accepted Charlie non-admin action fails
     - missing Alice no-invite-Dana proof fails
     - missing Dana post-removal admin-action proof fails
     - combined legacy booleans alone are not enough

10. Verify.
    - Run direct criteria tests.
    - Run analyzer on changed harness/criteria/test files.
    - Run scenario listing and discovery scripts.
    - Run focused group/admin tests touched by product changes, if any.
    - Run targeted reliability-sims scenario.
    - Record any non-target residuals without converting this session into GAPR-003/GAPR-004.

## Files To Edit

Expected:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Conditional:

- `integration_test/scripts/run_group_multi_party_device_real.dart` only if list/usage text needs a targeted update.
- `test/features/groups/application/*` only if a forbidden action is unexpectedly accepted by product code.
- `lib/features/groups/application/*` only with a failing direct regression proving a product-policy defect.

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

The existing GAPR-001 non-target `UP-001` stale-membership failure may be re-recorded as unrelated if unchanged. Do not claim a full green groups gate unless it actually passes.

Conditional direct tests:

```bash
flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart
```

Run these only if the implementation touches the corresponding product/application seam.

## Done Criteria

- `Status: execution-ready` is present before execution starts.
- GAPR-001 remains accepted and its targeted simulator pass is not weakened.
- Every GAPR-002 forbidden-action field is independently present and validated.
- Criteria tests prove missing or accepted forbidden-action evidence fails.
- No GAPR-003 system-event/convergence-field work is added.
- Targeted reliability-sims scenario passes with the expanded proof, or this session is blocked with exact evidence.
- Breakdown ledger is updated to `accepted` only after execution and closure audit accept the session.

## Scope Guard

Do not:

- Collapse multiple forbidden actions into one generic `StateUnchanged` boolean without action-specific outcomes.
- Remove existing final metadata, avatar, role, membership, removed-member, key epoch, state hash, self-delivery, or message-matrix assertions.
- Reclassify missing GAPR-003 event/version evidence as a GAPR-002 blocker.
- Fix the unrelated `UP-001` membership gate failure unless the GAPR-002 implementation directly touches that seam and reproduces it as in-scope.
- Accept a simulator pass if criteria would still accept the old combined-only proof shape.

## Reviewer Findings

Review verdict: sufficient.

- Session count impact: no split required; all forbidden-action matrix expansion shares the same harness and criteria proof seam.
- Missing tests/gates: none structurally. Criteria tests and targeted reliability-sims closure are mandatory.
- Product-risk control: product code is conditional on failing forbidden-action behavior; otherwise this is harness/criteria proof expansion.
- Dependency control: GAPR-003 remains out of scope.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Accepted differences:

- A pre-Dana remove-Dana attempt may be recorded as not applicable before join only if the post-Dana valid-current-member remove proof is present and criteria enforces that distinction.
- Remote no-op may be proven by active peer convergence checkpoints after each rejected-action group rather than per-action remote snapshots, as long as per-action local unchanged and outcome fields are present and the checkpoint covers active peers before the next successful group-control operation.
