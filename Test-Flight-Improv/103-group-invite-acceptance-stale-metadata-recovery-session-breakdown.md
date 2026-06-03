# 103 Group Invite Acceptance Stale Metadata Recovery - Session Breakdown

Status: reusable-breakdown

## Recommended Plan Count

Recommended plan count: 4

This breakdown is current-doc-only. It decomposes only
`Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
and does not execute implementation, test, pipeline, or closure work.

## Decomposition Artifact

- Decomposition artifact:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-breakdown.md`
- Source doc:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- Downstream workflow rule: detailed planning happens one session at a time.
  Later sessions must be refreshed against landed code before execution.
- Required intended plan path pattern:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-<session-id>-plan.md`

## Overall Closure Bar

After all sessions finish, User D can accept a group invite after User C has
changed the group to `test 3`, description `333`, and a new photo, without being
left in a stale or contradictory state. The accepted invite is no longer shown
as an actionable Accept card once the group is durably materialized, repeated
Accept attempts do not duplicate join timeline/status output or stored replay
envelopes, and User D's final All row, group header/details, and group photo
converge to the latest group identity. Existing A/B/C promoted-admin metadata,
demotion enforcement, avatar convergence, and four-user post-join text fan-out
remain intact.

## Source Of Truth

Docs opened for this decomposition:

- `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

No application source files were opened for this decomposition because the user
restricted reading to the source doc and directly referenced gate/matrix docs.
The likely code and test entry files below are taken from the source doc's named
facts and must be revalidated by each downstream plan against current code.

Gate source of truth:

- `Test-Flight-Improv/test-gate-definitions.md` defines
  `./scripts/run_test_gates.sh groups` as the Group Messaging Gate for group
  send, receive, retry, resume, invite, metadata/photo authority, and
  announcement behavior.
- `Test-Flight-Improv/14-regression-test-strategy.md` requires targeted
  permanent regressions for escaped production bugs and change-based subsystem
  gates for shared-path group work.

## Run Mode Snapshot

- Active mode: `standard`.
- Degraded local continuation explicitly allowed: no.
- Source proposal / closure doc path:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`.
- Source status vocabulary: this source doc is a spec/closure artifact, not a
  row-status matrix; session ledger statuses are `pending`, `accepted`,
  `accepted_with_explicit_follow_up`, `stale/already-covered`,
  `skipped_due_to_dependency`, `blocked`, and `prerequisite-blocked`.
- Overall closure bar: User D's accepted invite settles without a stale
  actionable Accept card, duplicate joined/status/replay output, or stale final
  All/details/photo identity, while existing A/B/C admin and four-user fan-out
  behavior remain intact.
- Final verdict policy: persist exactly one of `closed`,
  `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` after all
  runnable sessions resolve and ledger sanity passes.

## Controller Progress

- 2026-06-02: Doc-level pipeline fallback started after the spawned pipeline
  child wrote the run-mode snapshot and Session `01-accept-settlement`
  planning-intake draft, then stopped updating current-doc artifacts after a
  progress request. Continuing locally under the same session-pipeline
  contract from the existing current-doc breakdown and doc-scoped plan path.
- 2026-06-02: Controller run started for the existing current-doc breakdown.
  Ledger sanity found no final program verdict and all four sessions still
  `pending`; next action is Session `01-accept-settlement` plan preparation.

## Closure Progress

- 2026-06-02 17:22:27 CEST | Session `01-accept-settlement` closure audit
  completed | Files inspected: Session 01 plan, scoped accept-settlement
  production/test diffs, gate definitions, and this breakdown | Decision:
  landed evidence supports `accepted_with_explicit_follow_up`; broad groups gate
  instability remains an explicit Session 01 follow-up, not a product-code
  blocker | Next action: none in this closure pass; Sessions 02-04 remain
  pending and no final program verdict was written.
- 2026-06-02 18:01:50 CEST | Session `02-late-metadata-catchup` closure audit
  completed | Files inspected: Session 02 plan, source doc, scoped
  listener/test diffs, Session 01 dependency diffs, gate definitions, and this
  breakdown | Decision: landed evidence supports
  `accepted_with_explicit_follow_up`; Session 02 name/description metadata
  catch-up is accepted with only broad groups-gate instability as an explicit
  non-session-owned follow-up. No gate-definition update was needed because the
  added integration coverage lives in the already gate-owned
  `group_admin_metadata_convergence_test.dart` file | Next action: Session
  `03-avatar-byte-convergence` remains the next unresolved session, not started
  in this closure pass; Sessions 03-04 remain pending and no final program
  verdict was written.
- 2026-06-02 18:46:59 CEST | Session `03-avatar-byte-convergence` closure audit
  completed | Files inspected: Session 03 plan, source doc, scoped avatar proof
  diffs in `group_admin_metadata_convergence_test.dart` and
  `group_info_wired_test.dart`, resolved GCA-004 gate-follow-up diff in
  `invite_round_trip_test.dart`, gate definitions, and this breakdown |
  Decision: landed evidence supports `accepted`; Session 03 byte/SHA
  convergence and production upload-call ACL proof are closed with no
  production edits. The required groups gate is now green after the stale
  GCA-004 integration contract was aligned to Session 01's materialized
  bridge-error settlement. No gate-definition update was needed because Session
  03 added no new test file: the byte/SHA regression lives in existing Group
  Messaging Gate-owned `group_admin_metadata_convergence_test.dart`, and the
  upload ACL proof lives in existing feature-local presentation coverage |
  Next action: Session `04-scenario7-acceptance-closure` remains pending and no
  final program verdict was written.
- 2026-06-02 19:12:05 CEST | Session `04-scenario7-acceptance-closure`
  closure audit completed | Files inspected: Session 04 plan, source doc,
  scoped Scenario 7 host proof in `group_admin_metadata_convergence_test.dart`,
  existing simulator harness/script/criteria, gate definitions, and this
  breakdown | Decision: host Scenario 7 proof and the named groups gate passed,
  but final acceptance remained `still_open` at that point because no Scenario
  7-specific simulator path named
  `scenario7_group_invite_stale_metadata_recovery` existed or had passed. The
  older
  `regression_group_admin_permissions_and_message_reliability_four_users`
  simulator proof remains companion evidence only and does not cover pending
  invite UI, All/details/header copy, or repeated Accept UI behavior for the
  reported Scenario 7 | Next action: add and run the dedicated Scenario 7
  simulator proof, or explicitly downgrade the source simulator requirement
  before attempting final closure.
- 2026-06-02 20:55:02 CEST | Session `04-scenario7-acceptance-closure`
  simulator wiring follow-up completed | Files inspected: Session 04 plan,
  source doc, simulator harness/script/criteria, criteria tests, gate
  definitions, reliability simulation discovery output, and this breakdown |
  Decision: `scenario7_group_invite_stale_metadata_recovery` is now wired into
  the four-role multi-party harness, allowlisted by
  `run_group_multi_party_device_real.dart`, validated by
  `group_multi_party_device_criteria.dart`, covered by criteria tests, and
  discoverable through `./scripts/run_reliability_simulations.sh group --list`
  as item 88. Final acceptance remains `still_open` because the dedicated
  four-simulator proof has not yet been run to a passing verdict and the harness
  does not directly inspect the visible pending invite card/action, All row,
  header/details, or snackbar/status copy | Next action: run and pass the
  dedicated Scenario 7 reliability simulator scenario, then add or downgrade the
  UI-layer assertions before final closure if the source acceptance contract
  still requires visible UI proof.

## Session Ledger

| Session ID | Title | Classification | Intended Plan File | Depends On | Closure Status | Closure Evidence |
|---|---|---|---|---|---|---|
| `01-accept-settlement` | Accepted invite settlement and repeated-Accept idempotence | `implementation-ready` | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-01-accept-settlement-plan.md` | none | `accepted_with_explicit_follow_up` | Direct accept use-case and Group List tests passed; scoped diff settles materialized bridge-error invites and prevents duplicate retry output. `./scripts/run_test_gates.sh groups` initially failed twice, but the reported/focused slices `group_messaging_smoke_test.dart` and `ML-004` passed directly. During Session 03 gate-blocker recovery, stale GCA-004 expectations in `invite_round_trip_test.dart` were aligned to this materialized bridge-error settlement contract; the focused GCA-004 slice and full groups gate then passed. Status remains the historical Session 01 closure classification rather than a fresh Session 01 re-closure. |
| `02-late-metadata-catchup` | Late invitee metadata catch-up after accepted-inbox failure or replay skips | `evidence-gated` | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-02-late-metadata-catchup-plan.md` | `01-accept-settlement` | `accepted_with_explicit_follow_up` | Direct accept use-case and admin metadata convergence tests passed; scoped listener diff repairs equal-watermark signed metadata replays when the snapshot would update visible name/description fields, and regressions cover failed first accepted-inbox drain followed by later catch-up plus A/B/C/D late-invitee convergence to `test 3` / `333`. QA found no Session 02 blockers. `./scripts/run_test_gates.sh groups` exited 1, but focused rerun of `ST-003 fake-network randomized key epoch monotonicity keeps active epoch` passed, leaving broad gate instability follow-up only. No gate-definition edit was needed because the new integration case was added inside existing Group Messaging Gate file `group_admin_metadata_convergence_test.dart`. |
| `03-avatar-byte-convergence` | User-D avatar entitlement and byte convergence for post-invite photo updates | `evidence-gated` | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-03-avatar-byte-convergence-plan.md` | `01-accept-settlement`, `02-late-metadata-catchup` | `accepted` | Focused D-specific byte/SHA regression and production upload-call ACL widget proof passed; direct owner tests passed; constrained avatar-byte simulator proof passed for alice, bob, charlie, and dana. `./scripts/run_test_gates.sh groups` passed after stale GCA-004 expectations in existing gate-owned `invite_round_trip_test.dart` were updated to the resolved Session 01 settlement contract. Session 03 made no production edits and does not claim full Scenario 7 closure, which remains Session 04. |
| `04-scenario7-acceptance-closure` | Scenario 7 integration, simulator, gate, and closure evidence | `acceptance-only` | `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-04-scenario7-acceptance-closure-plan.md` | `01-accept-settlement`, `02-late-metadata-catchup`, `03-avatar-byte-convergence` | `still_open` | Focused host Scenario 7 proof passed in `group_admin_metadata_convergence_test.dart`, including stale `test 2` invite snapshot, post-invite `test 3` / `333` / latest-avatar replay, pending invite consumption, repeated Accept `notFound`, D-specific latest-avatar byte/SHA convergence, all four active member rows, and exactly-once post-join text fan-out. Supplemental direct replay proof, full owner file, focused GCA-004, focused Group List settlement, scoped `git diff --check`, and `./scripts/run_test_gates.sh groups` all passed. The dedicated simulator path is now wired as `scenario7_group_invite_stale_metadata_recovery`, criteria-tested, analyzer-clean, and discoverable in the group reliability simulator list. No production edits were made in Session 04. Final acceptance remains open because the required Scenario 7-specific four-simulator proof has not been run to pass and visible UI card/header/status assertions are not directly inspected by the new harness. |

## Final Program Verdict

Verdict: `still_open`

Report 103 is not closed. Sessions `01-accept-settlement`,
`02-late-metadata-catchup`, and `03-avatar-byte-convergence` remain accepted
under their recorded classifications, and Session 04 now has green host
evidence plus a dedicated, discoverable Scenario 7 multi-party simulator path.

The remaining closure gap is execution-specific: the new
`scenario7_group_invite_stale_metadata_recovery` scenario exists in the
multi-party real-device harness/script/criteria and is listed by the group
reliability simulator discovery flow, but no four-simulator run has passed yet.
The new harness criteria validate pending invite consumption, retry `notFound`,
final `test 3` / `333` / latest-avatar convergence, final active roles, and the
four-user message matrix, but they do not directly inspect the reported
user-visible pending invite card, All row, group details/header,
snackbar/status copy, or repeated Accept UI behavior.

Next required action: run and pass the dedicated Scenario 7 simulator proof, and
either add a narrow UI companion proof for the visible-state assertions or
explicitly revise this source doc's simulator acceptance requirement before
changing the verdict to `closed` or `accepted_with_explicit_follow_up`.

## Ordered Session Breakdown

### Session `01-accept-settlement`: Accepted Invite Settlement And Repeated-Accept Idempotence

- Session classification: `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-01-accept-settlement-plan.md`
- Exact scope: make the accept flow settle a durably materialized group without
  leaving the same pending invite visible as a fresh Accept action. Cover both
  bridge-error origins named by the source doc: join-with-config failure/timeout
  after materialization and accepted-inbox drain failure after materialization.
  Prevent repeated taps from publishing, storing, or rendering duplicate joined
  events/status for the same invite.
- Why it is its own session: this is the user-facing loop that makes the stale
  metadata bug confusing even before metadata recovery is fixed. It has a
  distinct application/UI settlement contract and can be verified independently.
- Likely code-entry files:
  `lib/features/groups/application/accept_pending_group_invite_use_case.dart`,
  `lib/features/groups/domain/models/pending_group_invite.dart`,
  `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`,
  `lib/features/groups/presentation/screens/group_list_wired.dart`,
  `lib/features/orbit/presentation/screens/orbit_wired.dart`
- Likely direct tests/regressions:
  `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`,
  `test/features/groups/presentation/group_list_wired_test.dart`,
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  and any focused direct regression needed for duplicate `member_joined`
  timeline/status or replay-envelope prevention.
- Likely named gates:
  direct tests first, then `./scripts/run_test_gates.sh groups` when the
  implementation touches group invite or metadata/photo authority paths.
- Matrix/closure docs to update when done:
  keep updates doc-scoped to Report 103 closure notes and classify any new
  high-value integration test in `Test-Flight-Improv/test-gate-definitions.md`
  if the downstream implementation adds one. Do not reopen Reports 90, 97, or
  98 unless actual regression evidence proves their accepted behavior changed.
- Dependency on earlier sessions: none.

### Session `02-late-metadata-catchup`: Late Invitee Metadata Catch-Up After Accepted-Inbox Failure Or Replay Skips

- Session classification: `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-02-late-metadata-catchup-plan.md`
- Exact scope: prove and, if needed, fix how User D converges from the
  send-time invite snapshot to User C's post-invite `test 3` name and `333`
  description after Accept. The plan must cover failed first accepted-inbox
  drain, later automatic catch-up without a repeated Accept tap, delivered but
  unapplied authoritative metadata replay, and close/skewed timestamp ordering
  around add-D, edit, and accept.
- Why it is its own session: metadata convergence depends on durable replay,
  cursor/drain behavior, metadata watermarks, soft-skip handling, and startup or
  resume catch-up. Those are different seams from pending invite settlement and
  from avatar byte transfer.
- Likely code-entry files:
  `lib/features/groups/application/accept_pending_group_invite_use_case.dart`,
  `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`,
  `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`,
  `lib/features/groups/application/group_message_listener.dart`,
  `lib/features/groups/application/send_group_invite_use_case.dart`,
  `lib/features/groups/application/group_invite_auth.dart`,
  `lib/features/groups/application/group_config_payload.dart`
- Likely direct tests/regressions:
  focused application tests in
  `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`;
  focused integration coverage extending or complementing
  `test/features/groups/integration/group_admin_metadata_convergence_test.dart`;
  direct proof that a sustained/non-transient accepted-inbox failure outlasts
  cursor self-healing before a later automatic catch-up converges to `test 3`.
- Likely named gates:
  direct tests first, then `./scripts/run_test_gates.sh groups`. If the final
  implementation touches startup/resume or bridge-level transport behavior, the
  downstream plan must decide whether `./scripts/run_test_gates.sh transport`
  is also required based on `Test-Flight-Improv/test-gate-definitions.md`.
- Matrix/closure docs to update when done:
  Report 103 closure notes and `Test-Flight-Improv/test-gate-definitions.md` if
  a new integration or orchestration test is added or reclassified.
- Dependency on earlier sessions:
  depends on `01-accept-settlement` so catch-up evidence does not rely on
  repeated Accept as the recovery trigger.

### Session `03-avatar-byte-convergence`: User-D Avatar Entitlement And Byte Convergence For Post-Invite Photo Updates

- Session classification: `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-03-avatar-byte-convergence-plan.md`
- Exact scope: prove and, if needed, fix D-specific access to the latest
  `test 3` avatar after User C adds User D and uploads a new group image before
  D accepts. The acceptance bar is not just matching `avatarBlobId` or
  `avatarMime`; User D must be entitled to download the blob, must have a
  supported non-empty local image file, and must have byte/SHA evidence matching
  the latest upload rather than the old invite snapshot image.
- Why it is its own session: avatar metadata and avatar bytes can diverge. The
  source doc identifies group media ACL and byte replacement as a separate
  entitlement/download surface from name/description metadata replay.
- Likely code-entry files:
  `lib/features/groups/presentation/screens/group_info_wired.dart`,
  `lib/features/groups/application/group_config_payload.dart`,
  `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`,
  `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  focused D-specific avatar proof extending or complementing
  `test/features/groups/integration/group_admin_metadata_convergence_test.dart`;
  a regression that fails when D has only avatar metadata but missing,
  unreadable, unauthorized, or old image bytes.
- Likely named gates:
  direct avatar/convergence tests first, then `./scripts/run_test_gates.sh groups`.
- Matrix/closure docs to update when done:
  Report 103 closure notes and `Test-Flight-Improv/test-gate-definitions.md` if
  new avatar convergence integration coverage is added or reclassified.
- Dependency on earlier sessions:
  depends on `01-accept-settlement` and `02-late-metadata-catchup` so the avatar
  proof runs after the group has a settled accept state and a defined metadata
  convergence path.

### Session `04-scenario7-acceptance-closure`: Scenario 7 Integration, Simulator, Gate, And Closure Evidence

- Session classification: `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-04-scenario7-acceptance-closure-plan.md`
- Exact scope: add or refresh the final Scenario 7 evidence across integration
  and simulator layers. The proof must show A/B/C setup preservation, C invites
  D before changing to `test 3`/`333`/latest image, D accepts afterward, the
  stale invite is not actionable, D converges to the latest identity and avatar
  bytes, repeated Accept cannot duplicate join evidence, and four-user post-join
  text fan-out remains exactly-once for active members.
- Why it is its own session: this validates the combined user journey across
  all previous sessions and should not be used as the first place to discover
  low-level accept, metadata, or avatar bugs.
- Likely code-entry files:
  `test/features/groups/integration/group_admin_metadata_convergence_test.dart`,
  `integration_test/group_admin_metadata_convergence_simulator_test.dart`,
  `integration_test/group_invite_accept_spinner_simulator_test.dart`,
  `Test-Flight-Improv/test-gate-definitions.md`,
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- Likely direct tests/regressions:
  focused Scenario 7 integration evidence and simulator evidence for pending
  invite card removal/filtering, truthful joined/catch-up copy, All/group
  details convergence, latest-avatar byte/SHA proof, repeated-Accept duplicate
  prevention, and four-user post-join fan-out.
- Likely named gates:
  final direct Scenario 7 tests, `./scripts/run_test_gates.sh groups`,
  `$run-flutter-host-gates` in fix-as-you-go mode for the `groups` host gate,
  and `$run-flutter-reliability-sims` in fix-as-you-go mode for the `group`
  scope as required by the source doc.
- Matrix/closure docs to update when done:
  Report 103 closure notes and `Test-Flight-Improv/test-gate-definitions.md`
  for any new integration, simulator, orchestration, nightly-only, or optional
  direct-suite classification. Do not create a new matrix doc unless downstream
  evidence proves there is no stable doc to extend.
- Dependency on earlier sessions:
  depends on `01-accept-settlement`, `02-late-metadata-catchup`, and
  `03-avatar-byte-convergence`.

## Why This Is Not Fewer Sessions

Fewer than 4 sessions would couple distinct failure modes that need independent
evidence:

- invite settlement and repeated-Accept idempotence can be fixed and tested
  before stale metadata convergence is solved;
- late metadata catch-up can pass while the latest avatar bytes still fail due
  to media entitlement or download behavior;
- avatar metadata can match while User D still has missing or old bytes;
- final Scenario 7 simulator proof must validate the landed combined behavior,
  not drive all implementation decisions in one broad pass.

## Why This Is Not More Sessions

More than 4 sessions would turn open root-cause alternatives into premature
architecture slices. Relay TTL/cap, recipient authorization filtering,
cursor-retry behavior, soft metadata skips, startup/resume drains, and
timestamp ordering should stay inside the late-metadata evidence-gated session
until downstream planning proves a concrete split is necessary. UI copy,
pending-card filtering, invite tombstoning/consumption, and duplicate join
prevention share the same accepted-invite settlement contract and should remain
one session. Avatar ACL and byte/SHA proof are one media-convergence session
rather than separate metadata-only and byte-only bookkeeping sessions.

## Regression And Gate Contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md`: this escaped bug
  needs permanent targeted regression coverage, not only broad smoke coverage.
- Follow `Test-Flight-Improv/test-gate-definitions.md`: group invite,
  metadata/photo authority, group recovery, and membership changes require the
  Group Messaging Gate, `./scripts/run_test_gates.sh groups`, after direct
  focused tests.
- Direct tests must run before named gates in each downstream execution pass.
- If a downstream session touches startup/resume or bridge-level transport
  behavior beyond group-local orchestration, that session must explicitly decide
  whether the Startup / Transport Gate applies.
- Session `04-scenario7-acceptance-closure` owns the final source-doc required
  evidence: focused Scenario 7 integration proof, simulator proof,
  `$run-flutter-host-gates` for `groups`, and `$run-flutter-reliability-sims`
  for the `group` scope.

## Matrix Update Contract

- Primary current-doc closure artifact: update
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
  during the closure pass with final evidence and accepted residual risks.
- Gate/matrix classification artifact: update
  `Test-Flight-Improv/test-gate-definitions.md` if any new integration,
  simulator, orchestration, nightly-only, optional/manual, or direct-suite test
  is added or reclassified.
- Do not reopen or mutate Reports 90, 97, or 98 unless downstream evidence
  proves an actual regression in their accepted behavior.
- Do not create a new matrix doc during planning by default. Reuse the current
  source doc and existing gate-definition doc unless the downstream closure
  pass proves there is no stable place to record the new evidence.

## Downstream Execution Path

Each session should next go through the downstream skills in this order:

| Session ID | Next Planning Step | Then Execution Step | Then Closure Step |
|---|---|---|---|
| `01-accept-settlement` | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| `02-late-metadata-catchup` | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| `03-avatar-byte-convergence` | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |
| `04-scenario7-acceptance-closure` | `$implementation-plan-orchestrator` | `$implementation-execution-qa-orchestrator` | `$implementation-closure-audit-orchestrator` |

Later sessions must refresh likely code-entry files, direct tests, and gate
requirements against landed code before executing.

## Reviewer And Arbiter Result

Reviewer answers:

- Recommended count: sufficient; not too coarse and not too fragmented.
- Sessions to merge: none.
- Sessions that must split: none at decomposition time.
- Missing tests or named gates: none structurally missing; downstream plans
  must fill exact direct regression commands after reading current code.
- Meaningful verified state: yes. Each implementation/evidence session can end
  with a focused direct regression plus the relevant group gate contract, and
  the final session validates the full Scenario 7 journey.
- Matrix-update responsibility: assigned to `04-scenario7-acceptance-closure`,
  with earlier sessions updating Report 103 or gate definitions only when they
  add or reclassify tests.
- Minimum safe session set: 4.

Arbiter classification:

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences: relay/backend changes, broad recovery redesign, and
  reopening Reports 90/97/98 are intentionally deferred unless downstream
  implementation evidence proves they are necessary.

## Structural Blockers Remaining

None.

## Accepted Differences Intentionally Left Unchanged

- No relay/backend session is recommended for the normal Scenario 7 window
  unless downstream evidence proves a concrete relay-side failure despite the
  source doc's non-destructive group-inbox, TTL, and cap facts.
- No broad Orbit, Intros, All, or Group Info redesign session is recommended.
  User-visible copy and stale Accept affordance work stay inside
  `01-accept-settlement`.
- No pre-join message or media backfill requirement is added.
- Reports 90, 97, and 98 remain closed unless real regression evidence
  contradicts their accepted outcomes.

## Exact Docs And Files Used As Evidence

Opened docs:

- `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Likely code and test files named by the source doc and used only as downstream
entry-point candidates:

- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/pending_group_invite.dart`
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `integration_test/group_admin_metadata_convergence_simulator_test.dart`
- `integration_test/group_invite_accept_spinner_simulator_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning And Execution

The breakdown separates the actual product risks by verification seam:
accepted-invite settlement, late metadata catch-up, avatar byte convergence,
and final Scenario 7 acceptance/closure. It keeps all intended plan paths
doc-scoped and non-colliding, assigns final gate and matrix responsibility, and
requires later sessions to refresh against landed code before execution. No
implementation or pipeline work has been executed by this decomposition.
