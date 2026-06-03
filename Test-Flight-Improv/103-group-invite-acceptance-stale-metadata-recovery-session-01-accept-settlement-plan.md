# Report 103 Session 01 Plan: Accepted Invite Settlement

Status: execution-ready

## Planning Progress

- 2026-06-02 17:07:12 CEST | Local fallback arbiter completed | Files inspected since last update: `accept_pending_group_invite_use_case.dart`, accept use-case tests, Group List/Orbit accept handlers, pending invite card, `test-gate-definitions.md` | Decision/blocker: plan is execution-ready for Session 01 only; no structural blocker | Next action: spawn fresh execution+QA for this plan.
- 2026-06-02 17:04:35 CEST | Local fallback planner completed | Files inspected since last update: bridge-error branches, GCA-004 tests, Group List bridgeError widget test, Orbit accept copy seam | Decision/blocker: current tests intentionally preserve the stale actionable invite loop and must be updated regression-first | Next action: reviewer/arbiter check.
- 2026-06-02 17:00:37 CEST | Evidence Collector started | Files inspected since last update: `implementation-plan-orchestrator` skill, Report 103 source doc, Report 103 session breakdown, existing Session 01 plan intake | Decision/blocker: confirmed doc-scoped path and current-session-only planning scope; no code implementation or closure will run | Next action: inspect current git status, accept-flow production files, direct tests, and gate definitions.

## Execution Progress

- 2026-06-02 17:14:04 CEST | Named gate finished | Files inspected or touched: gate output only | Command finished: `./scripts/run_test_gates.sh groups` | Decision/blocker: FAIL with one broad integration failure reported under `test/features/groups/integration/group_messaging_smoke_test.dart`; direct Session 01 tests already passed, classification pending focused triage | Next action: run suspected failing gate slice by name.
- 2026-06-02 17:18:25 CEST | Local execution fallback gate triage finished | Files inspected or touched: focused integration output only | Command finished: `flutter test test/features/groups/integration/group_messaging_smoke_test.dart` | Decision/blocker: PASS, all 85 tests passed; earlier broad gate failure did not reproduce in the reported failing slice | Next action: rerun `./scripts/run_test_gates.sh groups` once for final gate verdict.
- 2026-06-02 17:20:10 CEST | Local execution fallback gate triage finished | Files inspected or touched: focused membership output only | Commands finished: `./scripts/run_test_gates.sh groups` rerun failed with one broad parallel-gate failure; `flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending'` passed | Decision/blocker: direct Session 01 tests passed and both reported/focused failing integration slices pass in isolation; remaining groups-gate failure is classified as non-blocking broad gate instability for this session | Next action: closure audit for accepted-with-explicit-gate-follow-up.
- 2026-06-02 17:12:40 CEST | Named gate started | Files inspected or touched: gate script invocation only | Command running: `./scripts/run_test_gates.sh groups` | Decision/blocker: required Group Messaging Gate after direct tests | Next action: record result and triage failures if any.
- 2026-06-02 17:12:29 CEST | Direct test finished | Files inspected or touched: Group List widget test | Command finished: `flutter test test/features/groups/presentation/group_list_wired_test.dart` | Decision/blocker: PASS; bridge-error accept keeps joined group and recovery warning without pending invite row/action, while repair-pending tests still keep the invite visible | Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-06-02 17:12:01 CEST | Direct test started | Files inspected or touched: Group List widget test | Command running: `flutter test test/features/groups/presentation/group_list_wired_test.dart` | Decision/blocker: required Session 01 direct widget test | Next action: record result and triage failures if any.
- 2026-06-02 17:11:50 CEST | Direct test finished | Files inspected or touched: accept use-case test | Command finished: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: PASS; materialized bridge-error settlement, welcome tombstone, no duplicate publish/inboxStore/timeline retry, and repair-pending tests all passed | Next action: run Group List direct widget test.
- 2026-06-02 17:11:10 CEST | Direct test started | Files inspected or touched: accept use-case test | Command running: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: required Session 01 direct test | Next action: record result and triage failures if any.
- 2026-06-02 17:10:36 CEST | Executor production change completed | Files inspected or touched: `accept_pending_group_invite_use_case.dart`, accept use-case tests, Group List widget tests | Decision/blocker: materialized bridge-error paths now commit invite consumption/tombstone/delete when compatible local group state exists; repair-pending non-materialized branches unchanged | Next action: run required direct tests.
- 2026-06-02 17:09:40 CEST | Executor regression tests updated | Files inspected or touched: `accept_pending_group_invite_use_case.dart`, accept use-case tests, Group List widget tests, fakes for pending invites/messages/groups, incoming invite materialization | Decision/blocker: existing GCA-004 tests and Group List bridge-error widget assertion now encode materialized bridge-error settlement and no stale Accept retry; Orbit not touched because shared use-case and Group List surfaces cover Session 01 | Next action: implement production settlement changes.
- 2026-06-02 17:07:06 CEST | Executor local pass started | Files inspected or touched: session plan, `implementation-execution-qa-orchestrator` skill, `git status --short` | Decision/blocker: executing Session 01 only; unrelated dirty worktree changes will be preserved | Next action: inspect owner production and test files, then add failing regressions first where feasible.
- 2026-06-02 17:05:23 CEST | Executor bounded-wait status | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/presentation/group_list_wired_test.dart`, session plan | Decision/blocker: scoped regression diffs landed in the two direct test files; no production diff or test evidence yet, and child plan heartbeat is stale | Next action: allow only immediate Executor completion or terminate/classify no-progress before moving to QA/fix handling.
- 2026-06-02 17:05:23 CEST | Contract extracted | Files inspected or touched: session plan, `test-gate-definitions.md`, `git status --short` | Decision/blocker: scope is accepted-invite settlement only after durable group materialization; direct tests are accept use-case and Group List; named gate is `./scripts/run_test_gates.sh groups`; Orbit test is conditional if touched; dirty worktree is broad and unrelated changes must be preserved | Next action: spawn Executor.
- 2026-06-02 17:05:23 CEST | Executor spawn starting | Files inspected or touched: session plan only | Command running: `codex exec --model gpt-5.5 -c model_reasoning_effort="xhigh" ...` | Decision/blocker: local Codex CLI is available for spawned isolation | Next action: wait for Executor completion.
- 2026-06-02 17:05:23 CEST | Executor spawn retry | Files inspected or touched: session plan only | Command finished: initial `codex exec ... --ask-for-approval never ...` exited before materializing because this CLI expects approval policy as a top-level option | Decision/blocker: tool invocation issue only, no code/test changes from child | Next action: retry Executor spawn with corrected top-level approval option.

## Real Scope

Change only the accepted pending group invite settlement path after a group has
already been durably materialized. The session owns these behaviors:

- accepted-inbox drain failure after materialization must not leave the same
  pending invite visible as a fresh Accept action;
- join-with-config bridge failure/timeout after materialization must not leave
  the same pending invite visible as a fresh Accept action;
- repeated Accept after a materialized bridge-error state must not publish,
  store, or render duplicate `member_joined` timeline/status output;
- Group List and Orbit pending-invite surfaces must stop presenting the same
  invite as actionable once the group exists locally.

This session does not fix late `test 3` metadata catch-up, avatar byte
convergence, or the full Scenario 7 simulator journey. Those stay in Sessions
02, 03, and 04.

## Closure Bar

Session 01 is complete when direct tests prove that a materialized group plus a
bridge-error accept state consumes, tombstones, or filters the same invite so it
cannot be accepted again, while repair-pending join-material failures that do
not materialize a group remain retryable. Direct tests must cover both
bridge-error origins and duplicate joined-event prevention.

## Source Of Truth

- Source doc:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- Breakdown:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-breakdown.md`
- Gate definition:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests win over prose when they disagree.

## Session Classification

`implementation-ready`

## Exact Problem Statement

`acceptPendingGroupInvite` currently commits the accepted pending invite only
after accepted-inbox drain succeeds. When materialization succeeds but drain
fails, or when `materializeAcceptedGroupInvitePayload` reports bridge error
after local group state exists, the function returns `bridgeError` with a
`GroupModel` while the pending invite remains stored. Existing tests assert that
state. Re-entering Accept can then retry the materialized invite and can emit
duplicate joined timeline/status or replay envelopes.

## Files And Repos To Inspect Next

Primary owner files:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`

Secondary UI seams if direct tests show pending invite filtering is needed:

- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`

Do not touch late metadata replay, avatar ACL/download, relay storage, or
simulator harness files in this session unless a direct Session 01 test proves
they are required for invite settlement.

## Existing Tests Covering This Area

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  includes `GCA-004 inbox bridgeError keeps pending invite retryable until drain
  succeeds`, which currently locks in the bug for accepted-inbox failures.
- The same file includes `GCA-004 join bridgeError keeps welcome package
  retryable until retry succeeds`, which currently locks in the bug for
  join-with-config materialized bridge errors.
- `test/features/groups/presentation/group_list_wired_test.dart` includes
  `bridgeError accept keeps the joined group and shows recovery warning`, which
  currently expects the actionable pending invite card to remain visible.
- Existing repair-pending tests such as `IJ014 repairable join-material failure
  keeps pending invite without state or mailbox drain` must continue to prove
  that non-materialized key repair stays retryable.

## Regression/Tests To Add First

Update or add direct tests before product-code edits:

- accepted-inbox materialized bridge-error: expect a `bridgeError` result with a
  local group, pending invite removed/consumed/tombstoned or otherwise absent
  from pending surfaces, consumed invite recorded for single-use invites, and no
  second Accept path available for the same invite;
- join-with-config materialized bridge-error: same settlement expectations,
  including welcome key package tombstone when applicable;
- repeated Accept/idempotence: after a materialized bridge-error settlement,
  calling `acceptPendingGroupInvite` again for the same group returns
  `notFound`, `alreadyUsed`, or another non-joining settled result without
  additional `group:publish`, `group:inboxStore`, or local `member_joined`
  timeline rows;
- UI regression: Group List bridge-error accept should keep the joined group and
  recovery warning but no longer render
  `pending-group-invite-<groupId>` or an enabled Accept button for the same
  invite.

Add an Orbit widget regression only if Orbit has an existing focused pending
group invite bridge-error test surface that can be updated without broad test
fixture churn; otherwise record Orbit as covered by the shared use-case result
and leave full visible journey evidence to Session 04.

## Step-By-Step Implementation Plan

1. Add or rewrite the Session 01 direct tests above so they fail against the
   current behavior.
2. Refactor `accept_pending_group_invite_use_case.dart` to commit accepted
   invite settlement once local group materialization is durable, before
   returning a materialized `bridgeError`.
3. Ensure `_retryAcceptedMaterializedInvite` does not republish duplicate joined
   timeline/replay output for a group already settled by the same invite.
4. Keep repair-pending outcomes before durable materialization unchanged:
   invalid join material, missing key material, wrong identity, expired,
   revoked, invalid payload, and true duplicate-group mismatch must keep their
   existing semantics.
5. Update Group List and, if needed, Orbit tests to reflect that materialized
   bridge-error is a joined recovery state without an actionable stale invite.
6. Run the direct tests, then the Group Messaging Gate.

## Risks And Edge Cases

- Committing too early could mark truly repair-pending join-material failures as
  consumed. Guard the change to paths where a compatible local group/key exists.
- Consumed invite and welcome package tombstone writes must remain idempotent.
- Duplicate joined timeline rows can already exist from the first accept; the
  target is to prevent repeated Accept from adding more.
- UI lists may still receive a pending invite stream event after settlement;
  loading/filtering should prefer the current repository state.
- The broad worktree is dirty. Execution must preserve unrelated changes and
  compare scoped diffs before accepting the session.

## Exact Tests And Gates To Run

Direct tests:

```bash
flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test test/features/groups/presentation/group_list_wired_test.dart
```

Run if Orbit tests are touched:

```bash
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
```

Named gate after direct tests:

```bash
./scripts/run_test_gates.sh groups
```

Device/relay proof profile for Session 01: `host-only`. This session proves the
application settlement seam and widget pending-card state with host tests. The
source doc's full simulator and reliability proof remains required in Session
04 and must not be claimed here.

## Known-Failure Interpretation

If direct tests fail before implementation because they still expect the stale
pending invite loop, treat that as the intended red regression. If the named
groups gate exposes unrelated pre-existing failures in dirty files outside this
session, preserve the output, rerun the failing direct slice where possible, and
record the failure for closure review rather than weakening assertions.

## Done Criteria

- Direct use-case tests cover both materialized bridge-error origins.
- Direct tests prove repeated Accept cannot duplicate local joined timeline
  rows or `group:publish`/`group:inboxStore` replay output for the same settled
  invite.
- Group List no longer shows an actionable pending invite card after a
  materialized bridge-error join.
- Repair-pending non-materialized invite behavior remains retryable.
- Required direct tests pass, and `./scripts/run_test_gates.sh groups` is run or
  a concrete environment blocker is recorded.
- Session closure updates the breakdown ledger for `01-accept-settlement`.

## Scope Guard

Do not add a broad recovery architecture, relay/backend change, metadata replay
resync, avatar byte entitlement fix, simulator scenario, or UI redesign in this
session. Do not change invite authorization policy, group key policy, or
admin/member permission rules. Do not hide the recovery warning unless a direct
test proves the copy itself is the settlement bug.

## Accepted Differences / Intentionally Out Of Scope

- Latest `test 3` metadata convergence is Session 02.
- Latest avatar byte/SHA convergence is Session 03.
- Full four-user Scenario 7 integration/simulator evidence and
  `$run-flutter-reliability-sims` group scope are Session 04.
- Repair-pending join-material failures that do not create local group state
  intentionally remain retryable.

## Dependency Impact

Session 02 depends on this session so late metadata catch-up can proceed
without relying on repeated Accept taps. Session 03 depends on the same settled
join state before proving avatar bytes. Session 04 depends on all prior
sessions for full Scenario 7 closure.

## Reviewer Findings

- Structural blockers: none after adding host-only proof profile and explicit
  Session 04 simulator deferral.
- Incremental details: Orbit widget coverage is conditional because current
  focused Group List and shared use-case tests may be enough for this session.
- Accepted differences: full mobile simulator closure is intentionally deferred
  to Session 04 and cannot be used to close the overall source doc here.

## Arbiter Decision

The plan is execution-ready for Session `01-accept-settlement`. It is narrow,
test-first, uses doc-scoped artifacts, names direct tests and the required
Group Messaging Gate, preserves repair-pending behavior, and blocks scope drift
into metadata, avatar, or full Scenario 7 simulator work.

## Final Execution Verdict

Verdict: `accepted_with_explicit_follow_up`

Changed files:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-01-accept-settlement-plan.md`

Commands run:

```bash
flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test test/features/groups/presentation/group_list_wired_test.dart
./scripts/run_test_gates.sh groups
flutter test test/features/groups/integration/group_messaging_smoke_test.dart
./scripts/run_test_gates.sh groups
flutter test test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending'
```

Results:

- `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart`: PASS.
- `flutter test test/features/groups/presentation/group_list_wired_test.dart`: PASS.
- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart`: PASS, all 85 tests passed.
- Focused `ML-004` membership rerun: PASS.
- `./scripts/run_test_gates.sh groups`: run twice and failed once against
  `group_messaging_smoke_test.dart` and once against the broad parallel gate
  while showing `ML-004`; both named/focused reported slices passed when rerun
  directly. This remains an explicit non-blocking gate-instability follow-up
  for Session 01 closure, not a product-code blocker for accepted-invite
  settlement.

Closure evidence:

- Materialized accepted-inbox `bridgeError` now commits invite consumption and
  removes the pending invite when the local group exists.
- Materialized join-with-config `bridgeError` now commits invite consumption,
  records the welcome key package tombstone when applicable, and removes the
  pending invite when the local group exists.
- Repeated Accept after the settled materialized bridge-error state returns a
  non-joining settled result and does not add duplicate local joined timeline
  rows or duplicate `group:publish` / `group:inboxStore` output.
- Group List keeps the joined group and recovery warning while removing the
  stale pending invite row/action.
- Repair-pending non-materialized invite behavior remains covered by the direct
  use-case and widget test suites.
