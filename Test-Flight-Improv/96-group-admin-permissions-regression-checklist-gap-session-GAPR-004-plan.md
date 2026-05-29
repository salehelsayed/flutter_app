# Report 96 GAPR-004 Final Closure Plan

Status: accepted

## Execution Progress

- `2026-05-29 15:40:19 CEST` - Final no-code acceptance sweep passed. Commands: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` exit 0 with 537 tests; `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios` exit 0 and listed `regression_group_admin_permissions_and_message_reliability_four_users`; `./scripts/check_reliability_simulation_discovery.sh --records-tsv` exit 0 and retained the group runner classification; `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` exit 0 and retained the target scenario row; `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` exit 0 and listed the target as check `#87`; scoped `git diff --check` exit 0. Decision/blocker: final acceptance can rely on the GAPR-003 post-fix targeted simulator run `1780060893842` because no code-bearing changes landed after that run.
- `2026-05-29 15:40:19 CEST` - Stable docs and verdict reconciliation completed. Files updated: this plan, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, and `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`. Decision/blocker: GAPR-004 is accepted; final Report 96 verdict is `accepted_with_explicit_follow_up` because checklist coverage is complete, while the full named `groups` gate still has the unrelated `UP-001` stale-membership residual.

## Planning Progress

- `2026-05-29 15:40:19 CEST` - Local planning fallback completed after the spawned planner left only intake notes. Files inspected: Report 96 source doc, the Report 96 session breakdown, accepted GAPR-001/GAPR-002/GAPR-003 plans, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, current git status, and current scoped diffs. Decision/blocker: all implementation sessions are accepted; GAPR-004 can remain documentation and acceptance reconciliation only, with the full named `groups` gate truthfully classified under the known non-target `UP-001` residual. Next action: run the final lightweight acceptance sweep, then update the stable closure reference and breakdown final verdict.
- `2026-05-29 15:37:03 CEST` - Evidence Collector completed; Planner started. Files inspected since last update: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`, `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`, GAPR-001/GAPR-002/GAPR-003 plans, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: prerequisites are accepted; landed harness/criteria expose concrete Report 96 proof fields; final plan can be closure-only with UP-001 classified as a residual policy item. Next action: draft the execution-safe closure plan and checklist coverage ledger.
- `2026-05-29 15:35:55 CEST` - Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`; confirmed intended plan path did not already exist. Decision/blocker: create doc-scoped intake artifact before evidence collection. Next action: inspect Report 96 source doc, session breakdown, accepted prior session plans, test docs, and relevant named gate definitions.

## Real Scope

GAPR-004 performs final Report 96 acceptance and stable-doc reconciliation for `regression_group_admin_permissions_and_message_reliability_four_users`.

In scope:

- Reconcile the Report 96 checklist against accepted GAPR-001, GAPR-002, and GAPR-003 evidence.
- Confirm the scenario remains discoverable by stable `path:scenario` identity.
- Confirm the latest code-bearing acceptance evidence is still the post-GAPR-003 targeted reliability-sims pass.
- Update `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` with the final Report 96 status.
- Persist the final program verdict in `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`.
- Preserve the known non-target `UP-001` groups-gate residual without reopening unrelated group reliability work.

Out of scope:

- Product code or simulator harness changes.
- New criteria assertions beyond the accepted GAPR-001 through GAPR-003 proof.
- Changing gate classification in `Test-Flight-Improv/test-gate-definitions.md`.
- Rewriting Report 95 historical evidence.
- Fixing the unrelated `UP-001` stale-membership residual.

## Closure Bar

This session is accepted when:

- GAPR-001, GAPR-002, and GAPR-003 remain `Status: accepted`.
- The checklist coverage ledger below maps every Report 96 happy-path, edge-case, and regression-preservation item to accepted evidence.
- Final acceptance confirms no code changes landed after the GAPR-003 targeted simulator pass except documentation/ledger edits, or reruns the targeted simulator if code did change.
- The stable scenario identity remains listed/discoverable.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` records the final admin-permission checklist status.
- The breakdown ledger marks GAPR-004 accepted and records a final program verdict of `accepted_with_explicit_follow_up`, because the Report 96 checklist is covered while the full named `groups` gate still carries the unrelated `UP-001` residual.

## Source Of Truth

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md`
- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

## Checklist Coverage Ledger

| Report 96 requirement | Accepted evidence |
|---|---|
| Four roles Alice, Bob, Charlie, Dana and intended friendship graph | GAPR-001 targeted simulator pass `1780055021026`; GAPR-002 and GAPR-003 retained the same scenario identity and role proof |
| Existing Report 95 happy path is preserved | GAPR-001 accepted the baseline after fixing duplicate same-hash metadata/avatar recovery; later targeted simulator passes `1780057317153` and `1780060893842` preserved it |
| Bob, Charlie, demoted Bob, and removed Dana forbidden admin actions are independently represented | GAPR-002 accepted expanded action-specific proof and criteria tests |
| Rejected actions prove no actor-visible success, no local mutation, and no active remote mutation | GAPR-002 accepted blocked outcomes, unchanged local hashes, and remote no-op/convergence proof |
| Alice cannot invite Dana when they are not friends and Dana receives no invite | GAPR-002 accepted explicit Alice-Dana no-invite proof |
| Promotion, demotion, and removal events are user-visible through event/timeline surfaces | GAPR-003 accepted system-event visibility proof and criteria enforcement |
| Active members converge on metadata, avatar bytes/hash, members, admins, removed members, pending-invite state, latest event identity, state hash, key epoch, and available version/watermark fields | GAPR-003 accepted convergence-field proof, including the fix-pass latest-event signature comparison |
| Dana remains excluded from post-removal plaintext delivery and cannot send or administer after removal | GAPR-001 preserved removed-member message exclusion; GAPR-002 added removed-member admin-action rejection; GAPR-003 retained removed-member representation proof |
| Direct criteria tests reject missing or weakened proof | GAPR-002 criteria suite passed with 528 tests; GAPR-003 final criteria suite passed with 537 tests after the latest-event drift regression |
| Targeted simulator closes the final code-bearing proof | GAPR-003 final targeted reliability-sims pass `1780060893842` after the last code-bearing changes; proof passed for Alice, Bob, Charlie, and Dana |
| Named gate evidence is truthful | `./scripts/run_test_gates.sh groups` remains red only on the known non-target `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` stale-membership residual at `lib/features/groups/application/add_group_member_use_case.dart:281` |

## Execution Plan

1. Confirm accepted prerequisites.
   - Re-read the top status of the GAPR-001, GAPR-002, and GAPR-003 plans.
   - Confirm the breakdown ledger has those sessions accepted and GAPR-004 pending before final edits.

2. Run final no-code acceptance checks.
   - Run `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`.
   - Run scenario listing and discovery commands.
   - Run `run_with_devices.sh group --list`.
   - Run `git diff --check` over the touched code/test/doc files.
   - Do not rerun the four-device targeted simulator unless code changes after GAPR-003; documentation-only GAPR-004 edits do not invalidate run id `1780060893842`.

3. Update stable docs.
   - Add a concise Report 96 entry to `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`.
   - Do not change `_current-test-map.md` or `test-gate-definitions.md` unless the final acceptance sweep shows their guidance is stale. Current evidence says no gate classification changes are needed.

4. Persist final breakdown verdict.
   - Mark GAPR-004 accepted.
   - Add the final program verdict `accepted_with_explicit_follow_up`.
   - Include evidence commands, simulator run ids, and the explicit `UP-001` follow-up classification.

5. Closure audit.
   - Verify the final docs do not claim a green `groups` gate.
   - Verify the final docs do not claim product policy changes, new simulator framework, or closure for unrelated group reliability residuals.

## Tests And Gates

Final GAPR-004 checks:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios
./scripts/check_reliability_simulation_discovery.sh --records-tsv
./scripts/check_reliability_simulation_discovery.sh --checks-tsv
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
git diff --check -- Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-004-plan.md Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart
```

Accepted prior simulator evidence:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"
```

Latest accepted code-bearing run: exit 0, run id `1780060893842`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uB0JK3`, proof passed for `alice`, `bob`, `charlie`, and `dana`.

Known non-target residual:

```bash
./scripts/run_test_gates.sh groups
```

Latest accepted classification: exit 1 with `+311 -1`, isolated to `UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned` failing with `Bad state: Stale group membership event` at `lib/features/groups/application/add_group_member_use_case.dart:281`.

## Done Criteria

- This plan reaches `Status: accepted`: done.
- GAPR-004 execution notes record final check results: done.
- `20-group-discussion-reliability-closure-reference.md` records Report 96 as covered with an explicit `UP-001` follow-up: done.
- The breakdown ledger marks GAPR-004 accepted: done.
- The breakdown final program verdict is persisted as `accepted_with_explicit_follow_up`: done.

## Closure Audit

Verdict: accepted.

Findings:

- The final docs do not claim a green `groups` gate; they retain the known non-target `UP-001` stale-membership residual at `lib/features/groups/application/add_group_member_use_case.dart:281`.
- The final docs do not claim a product policy change, new simulator framework, or closure for unrelated group reliability programs.
- The final Report 96 checklist is covered by accepted GAPR-001, GAPR-002, and GAPR-003 evidence, with the latest code-bearing targeted simulator pass recorded as run id `1780060893842`.

## Scope Guard

Do not:

- Weaken accepted simulator criteria or proof requirements.
- Treat a documentation-only pass as a product-code fix.
- Claim `./scripts/run_test_gates.sh groups` is green while `UP-001` remains red.
- Update gate definitions without an actual gate-classification change.
- Reopen unrelated group reliability programs while closing Report 96.
