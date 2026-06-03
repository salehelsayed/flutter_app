# Session 04 Scenario 7 Acceptance Closure Plan

Status: execution-ready

## Status

Planning draft for Session `04-scenario7-acceptance-closure`.

Execution classification: `acceptance-only`.

This session may add or refresh tests, simulator harness criteria, and doc/gate classifications. Production code changes are blocked unless the combined Scenario 7 acceptance proof fails and identifies a new, scoped product defect. This plan must not write the final program verdict in the session breakdown; that belongs to execution and closure.

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-06-02 18:49:38 CEST | Intake | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`; `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-breakdown.md`; target plan path confirmed | Session `04-scenario7-acceptance-closure` and plan artifact confirmed; no blocker | Start Evidence Collector pass over scoped docs, prior session verdicts, direct host tests, simulator harnesses, and gate definitions |
| 2026-06-02 18:50:02 CEST | Evidence Collector started | Source doc, breakdown, Session 01-03 closure/verdict docs, named host tests, named simulator harnesses/scripts, `test-gate-definitions.md` queued | Acceptance-only posture preserved unless combined evidence proves a new product bug | Extract Session 04 contract, dependency evidence, existing coverage, simulator proof requirements, and gate commands |
| 2026-06-02 18:52:39 CEST | Evidence Collector completed / Planner started | Source acceptance bullets; breakdown Session 04 ledger; Session 01-03 closure rows and final verdicts; `group_admin_metadata_convergence_test.dart`; `invite_round_trip_test.dart`; `group_list_wired_test.dart`; simulator test/harness/script criteria; `test-gate-definitions.md`; dirty worktree status | No planning blocker. Existing lower seams cover settlement, metadata catch-up, and D avatar bytes, but no current test/harness closes the full Scenario 7 combined journey with active D and four-user fan-out | Draft acceptance-only plan with checklist proof ledger, simulator extension requirement, exact gates, and production-edit stop rule |
| 2026-06-02 18:56:47 CEST | Local controller fallback / Reviewer-Arbiter | Draft plan produced by spawned planner; source doc; breakdown ledger; existing Session 01-03 closure evidence | Spawned planner stalled before reviewer/arbiter completion after a progress request. Draft is sufficient once finalized with a stop rule: acceptance proof first, no production edits unless a new combined defect is isolated, and simulator closure must be explicitly classified if unavailable | Mark plan `execution-ready` and start Session 04 execution/QA under acceptance-only scope |

## Real Scope

In scope:

- Add or refresh one focused host integration proof for the full Scenario 7 journey in `test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
- Add or refresh simulator evidence for the same combined journey, using the narrowest existing surfaces:
  - `integration_test/group_admin_metadata_convergence_simulator_test.dart` if the host integration proof is exported as a simulator wrapper.
  - `integration_test/group_invite_accept_spinner_simulator_test.dart` for visible pending invite card/spinner/status behavior when a widget-level simulator proof is needed.
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/scripts/group_multi_party_device_criteria.dart` for real four-role A/B/C/D simulator proof.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if new direct or simulator suites are added or reclassified.
- Record execution evidence in this plan and the Report 103 closure notes during the later execution/closure pass, without writing the final program verdict into the breakdown during planning.

Out of scope unless a new combined proof fails with product evidence:

- Refactoring accept, metadata listener, avatar/media, relay, or transport production code.
- Reopening Sessions 01-03 lower-level implementation.
- Broad simulator-discovery rewrites beyond wiring the new Scenario 7 proof.
- Closing unrelated Report 98/102/104 work or broad dirty-worktree changes.

## Closure Bar

Session 04 is closed only when every item in this coverage ledger has a concrete passing proof, or a recorded blocker prevents execution:

| Requirement | Required proof |
| --- | --- |
| A/B/C setup preservation | Host integration and simulator verdicts show A/B/C friendship/setup, A creates the group, B becomes admin, metadata/photo convergence reaches A/B/C, B demotion and C promotion state remain correct before D is invited. |
| C invites/adds D before changing to `test 3` / `333` / latest image | Test chronology records D added/invited from the stale `test 2` snapshot before C publishes the `test 3` name, `333` description, and latest avatar. |
| D accepts afterward | D's accept occurs only after the post-invite C update is published/stored; proof records pending invite existed before Accept and accept result materialized the group. |
| Pending invite is not actionable after accept | Pending invite repository is empty or consumed for the group after accept, the accept button/card is absent in the UI proof, and a retry returns `notFound` or equivalent non-actionable result. |
| D converges to latest name/description/avatar bytes | D final group state is `test 3`, `333`, latest avatar blob/mime/path, readable supported image bytes, SHA-256 equal to latest upload, and SHA-256 different from the stale invite image. |
| Repeated Accept cannot duplicate join evidence | A repeated accept attempt after materialization cannot publish/store/render a second joined timeline/status/replay envelope; join evidence count stays exactly one. |
| Four-user post-join fan-out remains exactly-once for active members | A, B, C, and D each send one post-join text message; every other active member receives each message exactly once, with no sender-only, missing, or duplicate persistence. |
| Integration acceptance evidence | Focused host integration proof passes directly and is not replaced by lower seam tests alone. |
| Simulator acceptance evidence | A Scenario 7-specific simulator proof passes through `$run-flutter-reliability-sims`; if device availability blocks it, the session cannot close as accepted. |
| Group gate evidence | Direct tests pass and `./scripts/run_test_gates.sh groups` finishes green, or any failure is classified with focused rerun evidence and a non-session-owned blocker. |

## Source Of Truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md` is the acceptance contract for Scenario 7 behavior.
- `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-breakdown.md` is the session/dependency ledger. Its Session 04 entry is authoritative for this plan's scope.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named host gates and optional/manual suite classification.
- Prior dependency evidence:
  - Session 01: `accepted_with_explicit_follow_up`; GCA-004 was later aligned to materialized bridge-error settlement and the groups gate passed during Session 03 recovery.
  - Session 02: `accepted_with_explicit_follow_up`; name/description metadata catch-up accepted, with only historical broad groups-gate instability noted.
  - Session 03: `accepted`; D-specific avatar byte/SHA and upload-call ACL proof passed, constrained avatar simulator proof passed, and `./scripts/run_test_gates.sh groups` passed.

## Session Classification

`acceptance-only`.

The implementation pass should start by adding/refreshing acceptance proof. Product code stays untouched unless that proof fails and the failure is reduced to a new product defect that is not already owned by Sessions 01-03.

## Exact Problem Statement

Report 103 is not closed until the full four-user Scenario 7 journey is proven end to end. At planning time, the repo had lower-seam coverage for accepted invite settlement, late name/description catch-up, and D-specific avatar byte convergence, but no proof demonstrated the combined user journey: A/B/C setup remains valid, C invites D from stale metadata, C then updates to `test 3` / `333` / latest image, D accepts afterward, D cannot act on the old invite again, D converges to latest identity and avatar bytes, repeated Accept is idempotent, and four active members still receive post-join text exactly once.

User-visible behavior must improve only if the combined proof fails. Existing accepted behavior for Sessions 01-03 must stay unchanged.

## Files And Repos To Inspect Next

Primary acceptance/test files:

- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `integration_test/group_invite_accept_spinner_simulator_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

Only if new Scenario 7 simulator discovery wiring is required:

- `scripts/run_reliability_simulations.sh`
- `scripts/check_reliability_simulation_discovery.sh`

Only if the new proof fails and points to production:

- Return to the smallest owner file named by the failing assertion. Do not preemptively inspect or edit production code.

## Existing Tests

- `group_admin_metadata_convergence_test.dart` already contains A/B/C admin metadata/fan-out scenarios, Session 02 late invitee name/description catch-up to `test 3` / `333`, and Session 03 D avatar byte/SHA convergence.
- `invite_round_trip_test.dart` contains `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, proving consumed pending invite state, repeated accept returning `notFound`, and one joined timeline/status message in the bridge-error recovery path.
- `group_list_wired_test.dart` contains `bridgeError accept keeps joined group without stale pending invite action`, proving a materialized bridge-error accept removes the pending invite row/action and shows truthful recovery copy.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` wraps existing admin metadata convergence scenarios for simulator execution, but it does not expose full Scenario 7 acceptance.
- `integration_test/group_invite_accept_spinner_simulator_test.dart` proves the pending invite Accept spinner clears, the pending card is removed, and the group joins on a simulator, but only for a single seeded invite.
- `run_group_multi_party_device_real.dart` and its criteria now expose `scenario7_group_invite_stale_metadata_recovery` as a dedicated A/B/C/D multi-party scenario. `private_admin_metadata_intro_photo_convergence` is A/B/C only, and `regression_group_admin_permissions_and_message_reliability_four_users` removes Dana at the end, so neither is equivalent to Scenario 7's final active D fan-out requirement.

## Missing Coverage

- The focused host Scenario 7 chain now exists in `group_admin_metadata_convergence_test.dart` and is green.
- A dedicated multi-party simulator scenario now proves, at the harness/criteria layer, that D remains an active fourth member after accepting and participates in exactly-once post-join fan-out.
- Multi-party criteria now validate stale `test 2` / `222` invite capture, final `test 3` / `333` / latest-avatar byte convergence for D, pending invite consumption, retry `notFound`, final roles, and the four-user message matrix.
- Remaining coverage gap: the dedicated Scenario 7 mobile simulator scenario is wired and discoverable but has not yet been run through four simulators to a passing verdict in this session.
- Remaining UI-layer gap: the multi-party harness validates repository/result state but does not directly inspect a visible pending invite card/action, All row, group header/details text, or snackbar/status copy for Scenario 7.

## Regression/Tests To Add First

Add tests before considering any product edits:

1. Host integration proof in `group_admin_metadata_convergence_test.dart`, suggested name:
   `scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout`.

   It must independently assert every closure-ledger item: A/B/C setup, D invite before `test 3`, D accept after, pending invite consumed/non-actionable, final D metadata/avatar bytes, repeated Accept idempotence, and four-user exactly-once fan-out.

2. Simulator proof for the same journey. Preferred path:
   add a new multi-party scenario named `scenario7_group_invite_stale_metadata_recovery` in the real harness/scripts/criteria files, with roles `alice`, `bob`, `charlie`, and `dana`.

   Required verdict fields include: setup stage booleans, invite/update timestamps proving order, pending invite before/after counts, repeated accept result, join evidence counts by role, final D metadata fields, final D avatar SHA/byte length, active member peer IDs containing all four roles, and exactly-once message matrix counts.

3. If the multi-party harness cannot inspect the visible pending invite card/action state, add or refresh a narrow simulator UI proof in `group_invite_accept_spinner_simulator_test.dart` that uses stale invite copy, taps Accept, verifies card/action absence and truthful joined/catch-up copy, then records this as a UI-layer companion proof rather than a replacement for the four-role simulator.

4. Update `test-gate-definitions.md` only after adding a new direct/simulator proof so the new suite/scenario is discoverable and classified.

## Step-By-Step Implementation Plan

1. Confirm dirty worktree ownership before editing; preserve unrelated modified files and avoid broad formatting churn.
2. Add the host Scenario 7 test in `group_admin_metadata_convergence_test.dart` by reusing existing users, fake network, direct membership replay, byte-writing avatar downloader, SHA helpers, and pending-accept helpers.
3. Run the new host test directly. If it passes without production edits, keep the session acceptance-only.
4. If the host test fails, classify the failure:
   - test/harness expectation gap: fix only the test/harness;
   - new product bug: stop, document the smallest failing seam, and require a scoped implementation/fix plan before changing production code.
5. Add the simulator proof. Prefer a new `scenario7_group_invite_stale_metadata_recovery` scenario in `group_multi_party_device_real_harness.dart`, allowlist it in `run_group_multi_party_device_real.dart`, and validate it in `group_multi_party_device_criteria.dart`.
6. Add or refresh a simulator UI companion only if the multi-party proof cannot prove pending card/action absence and joined/catch-up copy.
7. Update `test-gate-definitions.md` for any new direct/simulator suite or optional/manual scenario.
8. Run focused direct tests first, then the group gate, then reliability simulator commands.
9. During execution/closure, update this plan with actual command results and update Report 103 closure notes. Do not write the final program verdict in the breakdown until the execution and closure audit complete.

## Risks And Edge Cases

- The stale invite snapshot may be legitimate at materialization time; final convergence, not initial card text, is the acceptance target.
- Same-timestamp or close-clock add-D/update-to-`test 3` ordering can hide replay bugs; the host proof should use equal or close timestamps where practical.
- D may miss live publish before Accept; the proof should not rely on GossipSub-only delivery.
- Avatar metadata can match while bytes are missing or stale; D-specific byte/SHA proof is mandatory.
- Repeated Accept after a materialized bridge-error must not republish duplicate joined evidence.
- Multi-party simulator failures can be device, relay, harness, or product issues; classify before fixing.
- Existing dirty worktree changes span many files; do not revert or normalize unrelated work.

## Device/Relay Proof Profile

- The final simulator layer is required because this journey spans group invite acceptance, membership, metadata/photo, avatar/media access, and multi-device message fan-out.
- The preferred Scenario 7 multi-party proof needs four roles: `alice`, `bob`, `charlie`, and `dana`. It therefore needs four booted iOS simulators or an existing reliability runner configuration that exports `DEVICE_A`, `DEVICE_B`, `DEVICE_C`, and `DEVICE_D`.
- Use the bundled reliability runner so device IDs and default relay addresses are resolved consistently:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:scenario7_group_invite_stale_metadata_recovery"
```

- The helper supplies `MKNOON_RELAY_ADDRESSES` if it is not already set. Do not accept a missing-relay skip path as proof.
- If fewer than four suitable simulators/devices are available, the execution can be evidence-gated but cannot close Session 04 as accepted.

## Exact Tests And Gates To Run

Focused host tests:

```bash
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout"
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "late_invitee_catches_up_name_description_after_stale_invite_snapshot"
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "late_invitee_catches_up_avatar_bytes_after_post_invite_photo_update"
flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"
flutter test test/features/groups/presentation/group_list_wired_test.dart --plain-name "bridgeError accept keeps joined group without stale pending invite action"
```

Simulator direct tests, if added/refreshed:

```bash
flutter test -d "$RELIABILITY_SINGLE_DEVICE_ID" integration_test/group_admin_metadata_convergence_simulator_test.dart --plain-name "scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout"
flutter test -d "$RELIABILITY_SINGLE_DEVICE_ID" integration_test/group_invite_accept_spinner_simulator_test.dart
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Reliability simulator gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only "integration_test/scripts/run_group_multi_party_device_real.dart:scenario7_group_invite_stale_metadata_recovery"
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group
```

Diff hygiene:

```bash
git diff --check
```

## Known-Failure Interpretation

- A direct Scenario 7 proof failure is actionable only after it is reduced to test/harness/environment/product. Do not classify it as a production bug by default.
- If `./scripts/run_test_gates.sh groups` fails, rerun the named failing file or `--plain-name` slice directly. Session 04 can only accept a red gate if the failure is proven unrelated and recorded as a blocker/follow-up; otherwise fix before closure.
- Existing gate definitions list known posts/privacy simulator startup failures; those are irrelevant to this group session.
- The multi-party runner is currently optional/manual in gate definitions. A missing Scenario 7 entry is a coverage gap, not a product regression.
- Device or relay unavailability blocks simulator acceptance; it must produce `evidence-gated` or `prerequisite-blocked`, not accepted.

## Done Criteria

- The plan's checklist coverage ledger has execution evidence for every item.
- The focused Scenario 7 host integration test passes.
- The lower-seam direct tests listed above still pass.
- `./scripts/run_test_gates.sh groups` passes, or any failure has focused rerun evidence and a reviewer-accepted non-session-owned classification.
- `$run-flutter-reliability-sims` group proof runs with a Scenario 7-specific simulator scenario and passes, including D active as the fourth member after accept.
- `test-gate-definitions.md` is updated if new direct/simulator proof files or scenarios are added.
- No production code changed unless a new combined acceptance defect was proven and separately scoped.
- The breakdown remains without a final program verdict until the later execution and closure audit.

## Scope Guard

- Do not use this session to redesign group invite architecture, avatar storage, relay retention, or message fan-out.
- Do not weaken existing assertions to make acceptance pass.
- Do not collapse D avatar byte proof into metadata/path equality.
- Do not replace the simulator closure gate with host tests.
- Do not reopen Sessions 01-03 unless the new proof directly contradicts their accepted dependency behavior.
- Do not touch unrelated dirty worktree files except where this session explicitly adds/refreshes tests or docs.

## Accepted Differences/Out Of Scope

- Existing A/B/C simulator coverage is reusable setup evidence but not final Scenario 7 closure.
- Existing four-user admin-permissions simulator coverage is not equivalent because it removes Dana at final state; it can provide patterns, not closure.
- A split simulator proof is acceptable only if the coverage ledger maps which layer proves each user-visible item. Host integration alone is not enough.
- Relay/backend changes are out of scope for the normal Scenario 7 window unless the Scenario 7 simulator proves relay behavior is the root cause.

## Dependency Impact

- Completion of this session is the prerequisite for a final Report 103 closure verdict.
- If Session 04 passes without production edits, Sessions 01-03 remain accepted under their existing classifications.
- If a new product bug is proven, execution should stop and create a scoped follow-up plan; final Report 103 closure remains open until that bug is fixed and this acceptance session reruns.
- If simulator devices are unavailable, mark closure evidence gated; do not advance the breakdown to final closure.

## Reviewer Findings

Local controller fallback review result: sufficient with no required split. The
plan has one acceptance owner, a concrete closure ledger, direct lower-seam
regression commands, a Scenario 7-specific host proof requirement, and a
simulator proof requirement. The only accepted adjustment is that execution may
close as `accepted_with_explicit_follow_up` rather than `accepted` if a
pre-existing simulator/device constraint prevents running the full new
multi-party proof after host and groups-gate evidence pass.

## Arbiter Decision

Execution-ready. Session 04 may proceed as an acceptance-only pass. Production
edits remain blocked unless the new combined proof is reduced to a new scoped
product defect. Planning fallback was used because the spawned planner stopped
at `planning-draft`; no additional planning session is required before
execution.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command / result | Decision / blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-06-02 18:58:04 CEST | Contract extracted / Executor running | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-04-scenario7-acceptance-closure-plan.md`; `Test-Flight-Improv/test-gate-definitions.md`; `test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; dirty worktree status | `git status --short` showed many unrelated dirty files, including scoped target files already modified | Acceptance-only scope confirmed. No production edits allowed unless the new combined proof isolates a new product defect. Child-agent spawn tooling is unavailable in this session, so execution proceeds as the scoped local fallback with file-backed evidence | Patch the focused host Scenario 7 proof first, then run its direct test |
| 2026-06-02 19:02:00 CEST | Host proof patched / structural validation starting | `test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-04-scenario7-acceptance-closure-plan.md` | `dart format test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed | Focused Scenario 7 host proof added with pending-invite consumption, repeated Accept idempotence, D avatar byte/SHA convergence, and four-user exactly-once fan-out assertions | Run the named Scenario 7 host test directly |
| 2026-06-02 19:03:07 CEST | Focused host test failed / triage | `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout"` failed: expected one joined inbox-store proof but counted zero | Classification: `test_observation_gap`, not product. Membership replay envelopes intentionally omit relay-visible `messageId`, so the proof should count the scoped `group:inboxStore` command for the accepted join while retaining joined timeline and publish assertions | Patch the inbox-store count helper, rerun the same focused host test |
| 2026-06-02 19:03:48 CEST | Focused host test passed / simulator feasibility check starting | `test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-04-scenario7-acceptance-closure-plan.md` | `dart format test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout"` passed (`00:00 +2: All tests passed!`) | Host acceptance proof is green without production edits. The first failure was narrowed to test observation and fixed in test code only | Inspect simulator harness/script/criteria for narrow Scenario 7 wiring feasibility |
| 2026-06-02 19:09:12 CEST | Dependency settlement checks passed | `test/features/groups/integration/invite_round_trip_test.dart`; `test/features/groups/presentation/group_list_wired_test.dart` | `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` passed (`00:00 +1: All tests passed!`); `flutter test test/features/groups/presentation/group_list_wired_test.dart --plain-name "bridgeError accept keeps joined group without stale pending invite action"` passed (`00:00 +1: All tests passed!`) | Session 01 settlement dependency remains aligned with the materialized bridge-error contract and the stale pending invite action stays removed in Group List | Run full owner integration file and named groups gate |
| 2026-06-02 19:10:43 CEST | Owner file and named gate passed | `test/features/groups/integration/group_admin_metadata_convergence_test.dart`; `./scripts/run_test_gates.sh groups` | `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed (`00:03 +16: All tests passed!`); `./scripts/run_test_gates.sh groups` passed (`00:55 +317: All tests passed!`) | Host Scenario 7 proof, supplemental direct replay proof, existing admin metadata/avatar coverage, and the Group Messaging Gate are green after the Session 04 test additions | Run scoped diff check and simulator-evidence classification |
| 2026-06-02 19:11:12 CEST | Diff and simulator evidence classified | 103-owned tracked production/test files; `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart` | `git diff --check -- lib/features/groups/application/accept_pending_group_invite_use_case.dart lib/features/groups/application/group_message_listener.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/group_admin_metadata_convergence_test.dart test/features/groups/integration/invite_round_trip_test.dart test/features/groups/presentation/group_list_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart` passed; `rg "scenario7_group_invite_stale_metadata_recovery|scenario7_late_invitee_acceptance|regression_group_admin_permissions_and_message_reliability_four_users" integration_test test/features/groups/integration Test-Flight-Improv/test-gate-definitions.md` found host Scenario 7 tests and the older four-user simulator scenario, but no `scenario7_group_invite_stale_metadata_recovery` simulator entry at that point | No production edit was needed and there is no whitespace blocker in the scoped 103-owned diff. At that point, the required dedicated Scenario 7 simulator proof was absent, so Session 04 could not be accepted or closed | Record final verdict as `still_open` on simulator-specific evidence |
| 2026-06-02 19:12:05 CEST | Read-only closure reviewer completed | Source doc, breakdown, Session 04 plan, focused host proof, and simulator harness/script/criteria | Reviewer found no host-proof blocker and recommended `still_open` because the source and plan require a Scenario 7-specific simulator proof that was not yet wired or run | Controller accepted the strict classification at that time: host/gate evidence passed, but final acceptance remained open on simulator proof | Persist plan, breakdown, and source-doc closure notes |
| 2026-06-02 20:55:02 CEST | Dedicated simulator path wired / discovery passed | `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `Test-Flight-Improv/test-gate-definitions.md`; this plan | `dart format` passed over the four touched Dart files; `flutter test test/integration/group_multi_party_device_criteria_test.dart` passed; `flutter analyze` on the touched Dart files passed; `dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario scenario7_group_invite_stale_metadata_recovery --list-scenarios` listed the new scenario; `./scripts/run_reliability_simulations.sh group --list` listed it as item 88; discovery TSV included the group orchestrator row | `$run-flutter-reliability-sims` can now target `scenario7_group_invite_stale_metadata_recovery`. The criteria catch stale invite snapshot, pending consumption, retry `notFound`, final latest metadata/avatar, final active roles, and exactly-once four-user fan-out. Final acceptance remains open because the four-simulator run was not executed to pass and visible UI card/header/snackbar state is not directly asserted by this harness | Persist path-wired documentation and leave final verdict `still_open` until device evidence passes |

## Final Execution Verdict

Status: `still_open`

Session 04 produced the required host Scenario 7 regression evidence and now
also wires a dedicated multi-party simulator scenario named
`scenario7_group_invite_stale_metadata_recovery`. The focused host proof
exercises the stale `test 2` invite snapshot, User C's post-invite `test 3` /
`333` / latest-avatar replay, pending invite consumption, repeated Accept
idempotence, D-specific latest-avatar byte/SHA convergence, all four active
member rows, and exactly-once post-join text fan-out. The new simulator
criteria enforce the same core state contract across alice, bob, charlie, and
dana, and discovery shows the scenario is available through the group
reliability simulator list.

The session cannot be marked `accepted` yet because the dedicated Scenario
7-specific mobile simulator proof has not been run through four simulators to a
passing verdict. The new multi-party harness also validates repository/result
state rather than directly inspecting the reported pending invite card, All row,
group details/header, snackbar/status copy, or repeated Accept UI behavior.

Required next action: run and pass
`scenario7_group_invite_stale_metadata_recovery` through `$run-flutter-reliability-sims`
with four devices, and either add a narrow UI companion proof for the visible
card/header/status assertions or formally downgrade that UI-specific acceptance
requirement before attempting final closure.
