# recommended plan count

Recommended plan count: 4

This rollout should run as four doc-scoped sessions:

1. `GAPR-001` stabilizes the already-added four-user scenario and resolves the known targeted simulator blocker before the checklist is widened.
2. `GAPR-002` expands forbidden admin-action coverage and remote no-op proof.
3. `GAPR-003` adds system-event visibility and richer convergence fields.
4. `GAPR-004` performs final simulator acceptance, matrix/doc reconciliation, and persists the final program verdict.

# run-mode snapshot

- Snapshot refreshed: `2026-05-29T10:59:37Z`
- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal/matrix/closure doc path: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- Source row/status vocabulary: session ledger statuses in this breakdown (`pending`, `accepted`, `accepted_with_explicit_follow_up`, `blocked`, `skipped_due_to_dependency`, `stale/already-covered`) plus source-doc checklist items without a separate matrix row table.
- Overall closure bar: the Report 96 checklist is closed only when the four-user admin-permissions simulator scenario remains discoverable and proves the forbidden-action, system-event, convergence-field, removed-member, direct-test, groups-gate, and targeted reliability-sims evidence listed below.
- Final verdict policy for this run: use `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` per the active pipeline skill; `closed` requires all four sessions accepted and the final program acceptance pass to persist a trustworthy verdict.

# decomposition artifact

- Artifact path: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-breakdown.md`
- Source doc path: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- Downstream workflow rule: detailed planning happens one session at a time. Later sessions must refresh against landed code, current simulator evidence, and this ledger before execution.
- Intended plan path rule: every session plan must be doc-scoped as `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-<session-id>-plan.md`.

# overall closure bar

The rollout closes only when `regression_group_admin_permissions_and_message_reliability_four_users` is still discoverable through the group multi-party simulator path and proves the full checklist from Report 96:

- four roles Alice, Bob, Charlie, and Dana use the intended friendship graph and scenario identity
- the current happy path from Report 95 remains covered without weaker final-state, avatar, role, membership, key epoch, state hash, or message-matrix assertions
- forbidden admin actions are independently represented for non-admin, demoted-admin, and removed-member states where applicable
- rejected actions prove no actor-visible success, no local state mutation, and no remote active-peer mutation
- promotion, demotion, and member-removal events are user-visible to relevant group members through the app's existing event/timeline surface
- active members converge after each group-control operation on metadata, avatar bytes/hash, active members, admins, removed members, pending-invite state where relevant, latest event identity, group state version where available, state hash, and key epoch where encrypted
- Dana remains excluded from post-removal plaintext delivery and cannot perform sends or admin actions after removal
- required structural checks, direct host tests, `groups` gate, discovery checks, and targeted `$run-flutter-reliability-sims` closure are passed or truthfully classified under the known-failure policy

Allowed final program verdicts for this breakdown are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`. A verdict is not trustworthy if it only preserves the current partial Report 95 scenario while leaving any Report 96 checklist gap silently unmapped.

# source of truth

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md` is the product/test intent source for the checklist gap.
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md` records the existing scenario implementation and the current targeted simulator blocker.
- `Test-Flight-Improv/14-regression-test-strategy.md` requires targeted permanent regressions, matching gates by blast radius, and no broad smoke-test inflation.
- `Test-Flight-Improv/test-gate-definitions.md` classifies `integration_test/scripts/run_group_multi_party_device_real.dart` as a manual simulator orchestrator and keeps `./scripts/run_test_gates.sh groups` as the named group messaging gate.
- `Test-Flight-Improv/_current-test-map.md` maps group send, invite, membership, metadata/photo authority, and promoted-admin invite propagation to the groups gate plus targeted direct suites.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` is the stable group reliability closure reference to update if this checklist changes release-confidence claims.
- `integration_test/group_multi_party_device_real_harness.dart` owns the four-role app-instance choreography and scenario proof payloads.
- `integration_test/scripts/group_multi_party_device_criteria.dart` owns scenario registration, role requirements, proof-message expectations, and scenario-specific proof validation.
- `integration_test/scripts/run_group_multi_party_device_real.dart` owns scenario selection/listing and the stable `path:scenario` target used by the reliability-sims wrapper.

# session ledger

| session id | title | classification | intended plan file | depends on | initial status |
|---|---|---|---|---|---|
| GAPR-001 | Stabilize current four-user scenario baseline | evidence-gated | `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md` | none | accepted |
| GAPR-002 | Expand forbidden admin-action rejection matrix | implementation-ready | `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md` | GAPR-001 | accepted |
| GAPR-003 | Add system-event and convergence-field proof | evidence-gated | `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md` | GAPR-001 | accepted |
| GAPR-004 | Final simulator acceptance and closure reconciliation | closure-only | `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-004-plan.md` | GAPR-002, GAPR-003 | accepted |

# ordered session breakdown

## GAPR-001 - Stabilize current four-user scenario baseline

- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-001-plan.md`
- Exact scope: triage and resolve the current `regression_group_admin_permissions_and_message_reliability_four_users` targeted simulator blocker recorded in Report 95 before widening checklist assertions. The known failure evidence is Bob timing out in `_waitForGroupMetadata` at `after_charlie_metadata_v2`, with another attempt exposing Dana failing to converge at `after_alice_avatar_v3`.
- Why it is its own session: Report 96 expands checklist coverage, but adding assertions on top of a currently red scenario would make failure attribution ambiguous. This session produces a stable baseline or a truthful blocker classification first.
- Likely code-entry files: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and product seams only if the failing targeted run proves a real group metadata/avatar propagation defect.
- Likely direct tests/regressions: `dart analyze integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart integration_test/group_admin_metadata_convergence_simulator_test.dart`; `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario all --list-scenarios`; `./scripts/check_reliability_simulation_discovery.sh --records-tsv`; `./scripts/check_reliability_simulation_discovery.sh --checks-tsv`; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `flutter test integration_test/group_admin_metadata_convergence_simulator_test.dart` when a simulator device is available.
- Likely named gates: `./scripts/run_test_gates.sh groups`; targeted `$run-flutter-reliability-sims` group `--only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"`.
- Matrix/closure docs to update when done: Report 95 plan status/evidence if still authoritative, this breakdown ledger, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` only if a product reliability defect is fixed or newly classified.
- Dependency on earlier sessions: none.

## GAPR-002 - Expand forbidden admin-action rejection matrix

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-002-plan.md`
- Exact scope: extend the four-user scenario and criteria so forbidden admin options are independently observable rather than represented by combined or inferred checks. Cover non-admin Bob before promotion, non-admin Charlie, demoted Bob before and after Dana joins, Alice's non-friend Dana invite rejection, and Dana after removal. Each rejected action must report no actor-visible success, no local mutation, and no active remote mutation.
- Why it is its own session: this is the checklist's authorization-rejection seam. It is different from system-event visibility and convergence watermarks, and it can be verified through the existing scenario proof payload and criteria validator once the baseline is stable.
- Likely code-entry files: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart` only if selector/listing text must be adjusted, plus narrow group admin application tests if a forbidden action is not rejected by product code.
- Likely direct tests/regressions: direct analyzer/discovery checks from GAPR-001; targeted host tests around `test/features/groups/integration/group_admin_metadata_convergence_test.dart` and any narrower group admin/member-role tests touched by product fixes; targeted reliability-sims `group --only` scenario.
- Likely named gates: `./scripts/run_test_gates.sh groups`; targeted `$run-flutter-reliability-sims` scenario closure.
- Matrix/closure docs to update when done: this breakdown ledger and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` if the new proof changes group reliability closure claims.
- Dependency on earlier sessions: GAPR-001.

## GAPR-003 - Add system-event and convergence-field proof

- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-003-plan.md`
- Exact scope: add observable proof for promotion, demotion, and member-removal system events, and expand convergence proof to compare pending-invite state where relevant, latest group event identity, group state version where available, removed-member representation, avatar metadata/bytes/hash, state hash, and key epoch across active members.
- Why it is its own session: this touches event/timeline evidence and state-version observability, which may use different app-layer repositories or proof surfaces than action rejection. The source doc intentionally leaves the exact evidence shape open, so planning must first verify the existing event and state fields before implementation.
- Likely code-entry files: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, group event/timeline repository helpers if needed, pending-invite repository helpers if needed, and narrow tests beside the affected repository/application seam if a proof field is not currently exposed.
- Likely direct tests/regressions: analyzer/discovery checks from GAPR-001; focused group event, pending invite, or metadata convergence tests identified during planning; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `flutter test integration_test/group_admin_metadata_convergence_simulator_test.dart` when available; targeted reliability-sims `group --only` scenario.
- Likely named gates: `./scripts/run_test_gates.sh groups`; targeted `$run-flutter-reliability-sims` scenario closure. Add `transport` only if lifecycle/resume/reconnect code is changed.
- Matrix/closure docs to update when done: this breakdown ledger, `Test-Flight-Improv/_current-test-map.md` if manual simulator evidence wording changes, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` if the closure reference now cites the expanded admin-permission proof.
- Dependency on earlier sessions: GAPR-001.

## GAPR-004 - Final simulator acceptance and closure reconciliation

- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap-session-GAPR-004-plan.md`
- Exact scope: reconcile all Report 96 checklist items against the landed scenario, criteria validator, direct tests, named gates, and simulator evidence. Persist the final program verdict in this breakdown and update stable docs without reopening unrelated group reliability work.
- Why it is its own session: the final acceptance depends on both checklist expansion sessions and must evaluate the whole scenario contract rather than one code seam.
- Likely code-entry files: no product code expected; docs only unless final acceptance finds a concrete missing assertion that belongs to GAPR-002 or GAPR-003.
- Likely direct tests/regressions: `dart analyze` on scenario files, scenario list command, discovery scripts, focused group host tests, `./scripts/run_test_gates.sh groups`, `$run-flutter-reliability-sims group --list`, and targeted `$run-flutter-reliability-sims group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"`.
- Likely named gates: `./scripts/run_test_gates.sh groups`; targeted reliability-sims closure is required. Broader group reliability sweep remains optional unless product changes widen blast radius.
- Matrix/closure docs to update when done: this breakdown final program verdict, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/_current-test-map.md` if necessary, and `Test-Flight-Improv/test-gate-definitions.md` only if gate classification changes.
- Dependency on earlier sessions: GAPR-002 and GAPR-003.

# why this is not fewer sessions

Fewer than four sessions would couple unstable baseline triage, authorization rejection expansion, event/convergence proof work, and final acceptance into one large simulator task. That would make a red targeted run hard to classify: a failure could be the existing Report 95 metadata/avatar convergence blocker, a new forbidden-action assertion, a missing event surface, or a final evidence/documentation mismatch. The chosen split leaves meaningful verified states after each step.

# why this is not more sessions

The source doc lists many forbidden cases, but they share the same scenario harness, rejected-action proof shape, criteria validator, and targeted simulator gate. Splitting every actor/action pair into separate sessions would create bookkeeping without independent verification value. System events and convergence fields are grouped because both are evidence-surface work over the same group-control transitions.

# regression and gate contract

- Add or adjust targeted regressions before relying on broad smoke coverage.
- Use `./scripts/run_test_gates.sh groups` for group send, receive, invite, membership, metadata/photo authority, and promoted-admin invite propagation changes.
- Keep `integration_test/scripts/run_group_multi_party_device_real.dart` as a manual simulator orchestrator in gate docs unless the gate definitions are intentionally widened.
- Keep the targeted reliability-sims command as the required closure gate for this rollout:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users"
```

- Run `transport` only when implementation changes lifecycle, startup, resume, reconnect, or bridge transport behavior.
- Classify simulator/device allocation failures separately from code failures, with exact command, run id, and failing role/stage.

# matrix update contract

No new matrix doc should be invented for this rollout. Update existing stable docs only:

- This breakdown owns the session ledger and final program verdict.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` should record the final admin-permission checklist status only after GAPR-004.
- `Test-Flight-Improv/_current-test-map.md` should be updated only if the manual simulator evidence or group gate guidance changes.
- `Test-Flight-Improv/test-gate-definitions.md` should be updated only if this work intentionally changes gate classification.
- Report 95 should remain historical evidence for the first four-user scenario implementation; do not rewrite it into Report 96 closure unless a session needs to append truthful status.

# downstream execution path

Each runnable session followed the doc-scoped downstream path:

- `GAPR-001` went through planning, execution/QA, and closure audit and is accepted.
- `GAPR-002` went through planning, execution/QA, and closure audit and is accepted.
- `GAPR-003` went through planning, execution/QA, a bounded fix pass, and closure audit and is accepted.
- `GAPR-004` went through planning, acceptance/doc reconciliation, and closure audit and is accepted.

# final program verdict

Verdict: `accepted_with_explicit_follow_up`

Recorded: `2026-05-29 15:40:19 CEST`

Report 96 is accepted because:

- `GAPR-001`, `GAPR-002`, `GAPR-003`, and `GAPR-004` are all accepted.
- The four-user scenario remains discoverable as
  `integration_test/scripts/run_group_multi_party_device_real.dart:regression_group_admin_permissions_and_message_reliability_four_users`.
- The final code-bearing targeted simulator pass is GAPR-003 run id
  `1780060893842`, shared dir
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_regression_group_admin_permissions_and_message_reliability_four_users_uB0JK3`,
  with proof passed for `alice`, `bob`, `charlie`, and `dana`.
- The final GAPR-004 no-code acceptance sweep passed: criteria suite `537`
  tests, scenario listing, discovery records, discovery checks,
  `run_with_devices.sh group --list`, and scoped `git diff --check`.
- Stable closure reference
  `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  records the Report 96 status.

Explicit follow-up:

- The full named `./scripts/run_test_gates.sh groups` gate remains red only on
  the known non-target `UP-001 create add remove and re-add keep DB and bridge
  groupConfig snapshots aligned` stale-membership residual at
  `lib/features/groups/application/add_group_member_use_case.dart:281`.
  This follow-up does not block Report 96 checklist closure and must not be
  misreported as a failure of the four-user admin-permission scenario.

# reviewer pass

- Is the recommended session count sufficient, too coarse, or too fragmented? Sufficient. It isolates the known red baseline, action-rejection coverage, event/convergence evidence, and final acceptance.
- Which proposed sessions should merge? None. GAPR-002 and GAPR-003 are related but have different proof surfaces and failure attribution.
- Which proposed sessions must split? None at decomposition time. GAPR-002 should only split during planning if current code proves a product-policy defect separate from harness proof expansion.
- What tests or named gates are missing from the decomposition? None structurally. Device-backed simulator closure is required, while broader group sweep and transport gate are conditional.
- Does each session end in a meaningful verified state? Yes: stable baseline, expanded rejection proof, expanded event/convergence proof, and final verdict.
- Is matrix-update responsibility assigned clearly? Yes. GAPR-004 owns stable doc reconciliation; earlier sessions update only their ledger/status and directly affected closure notes.
- Minimum safe session set: the four sessions listed above.

# arbiter

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences: the exact system-event and state-version evidence shape remains open until GAPR-003 planning inspects the current app-layer surfaces, matching the source doc's accepted ambiguity.

# accepted differences intentionally left unchanged

- The stable scenario identity remains `regression_group_admin_permissions_and_message_reliability_four_users`; command number 87 is local ordering evidence only.
- The rollout does not require a new simulator framework or new gate classification.
- The rollout does not redefine group admin policy; it hardens evidence for the existing policy.
- The full group reliability sweep is not required unless product changes widen blast radius beyond this scenario.

# exact docs/files used as evidence

- `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`

# why the decomposition is safe to send into downstream planning/execution

The artifact is doc-scoped, uses non-colliding plan paths, names the current source and evidence files, keeps the known existing simulator failure as the first prerequisite, assigns final doc reconciliation to a closure session, and preserves the batch pipeline's required downstream path without inventing additional retry layers.
