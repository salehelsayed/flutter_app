# 103 Session 02 Plan: Late Metadata Catch-Up

Status: execution-ready

## Planning Progress

- 2026-06-02 17:31:18 CEST | Local fallback arbiter completed | Files inspected since last update: Report 103 source/breakdown, Session 01 closure ledger, accept/materialization/drain/listener metadata seams, gate definitions, group admin metadata convergence helpers | Decision/blocker: plan is execution-ready for metadata catch-up only; no structural blocker | Next action: spawn fresh execution+QA for this plan.
- 2026-06-02 17:29:54 CEST | Local fallback reviewer completed | Files inspected since last update: owner files and targeted `rg` evidence for metadata watermarks, pre-join replay skip, authoritative config application, accepted-inbox drain failures, startup/resume callers | Decision/blocker: plan must prove both failed first drain and delivered-but-unapplied replay paths; avatar byte proof remains Session 03 | Next action: arbiter classification.
- 2026-06-02 17:25:07 CEST | Evidence Collector completed / Planner started | Files inspected since last update: accept use case, invite materialization, group offline inbox drain, metadata listener, config payload, startup/resume/retrier callers, accept use-case tests, group admin metadata convergence helpers, fake group network/user fixtures | Decision/blocker: no planning blocker; evidence supports a narrow implementation plan. Session 01 settlement is visible in current tests/code and should not be reopened. | Next action: write execution-safe plan.

## Execution Progress

- 2026-06-02 17:53:20 CEST | Current-doc progress state after user request | Files inspected or touched: session plan only | Command: none | Decision/blocker: Executor pass is complete and no new scope is started; changed Session 02 paths are `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, and this plan. Executor-reported results: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed; `./scripts/run_test_gates.sh groups` failed in broad smoke coverage; focused rerun `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` passed, classifying the broad groups-gate failure as non-session-owned for this metadata catch-up session; `git diff --check` passed for tracked changed code/test files per Executor handoff. Separate QA Reviewer is currently running, so final execution verdict is still pending. | Next action: wait for QA Reviewer result; run a fix pass only if QA reports blocking findings.
- 2026-06-02 17:51:55 CEST | QA Reviewer spawned/running | Files inspected or touched: session plan, Executor result handoff, owner diffs | Command: `codex -a never -s danger-full-access -m gpt-5.5 -c reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app exec -o /tmp/session02-qa-result.md` | Decision/blocker: Executor completed implementation and gate classification; separate QA Reviewer must inspect scope, regressions, touched files, direct test evidence, groups-gate classification, and dirty-worktree preservation before final verdict | Next action: wait for QA Reviewer result and run a fix pass only for blocking findings.
- 2026-06-02 17:50:31 CEST | Focused groups-gate rerun finished / Executor completion recorded | Files inspected or touched: `test/features/groups/integration/group_messaging_smoke_test.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` | Decision/blocker: focused rerun passed, so the `./scripts/run_test_gates.sh groups` exit 1 is classified as broad-gate instability/non-session-owned for this metadata catch-up session; required direct suites passed and changed seams compiled through direct tests | Next action: hand off to separate QA Reviewer.
- 2026-06-02 17:48:58 CEST | Groups gate finished with broad failure / focused rerun started | Files inspected or touched: `scripts/run_test_gates.sh`, `test/features/groups/integration/group_messaging_smoke_test.dart` | Command: `./scripts/run_test_gates.sh groups`, `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` | Decision/blocker: named groups gate exited 1; failure surfaced in broad smoke area, first reported/current failing slice was `group_messaging_smoke_test.dart` `ST-003`, outside this session's metadata catch-up owner files | Next action: rerun reported focused slice directly and classify.
- 2026-06-02 17:47:19 CEST | Direct tests finished / groups gate started | Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `./scripts/run_test_gates.sh groups` | Decision/blocker: final formatted application direct suite passed; direct tests provide fastest structural compile validation for changed listener/test seams; starting required named gate | Next action: triage groups gate result and rerun focused slice if broad instability recurs.
- 2026-06-02 17:46:53 CEST | Direct integration test finished / application direct rerun started | Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `lib/features/groups/application/group_message_listener.dart` | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: full integration direct suite passed after focused setup fix; rerunning application direct after formatter touched its file | Next action: verify application direct suite in final formatted state.
- 2026-06-02 17:46:23 CEST | Focused integration rerun finished / full integration rerun started | Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `lib/features/groups/application/group_message_listener.dart` | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name late_invitee_catches_up_name_description_after_stale_invite_snapshot`, `dart format lib/features/groups/application/group_message_listener.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Decision/blocker: focused integration passed after seeding Alice's key; formatted touched Dart files before rerunning full direct suite | Next action: verify full integration direct suite.
- 2026-06-02 17:45:51 CEST | Focused integration rerun started | Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name late_invitee_catches_up_name_description_after_stale_invite_snapshot` | Decision/blocker: seeded initial group key for the new invite flow setup | Next action: verify focused integration case.
- 2026-06-02 17:45:31 CEST | Direct integration test failed / focused rerun classified | Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name late_invitee_catches_up_name_description_after_stale_invite_snapshot` | Decision/blocker: full file had one failure; focused rerun shows new integration setup missed inviter key seeding (`User A has group key`), not a production metadata failure | Next action: seed the initial group key using the file's existing `_saveKey` helper and rerun focused integration.
- 2026-06-02 17:44:55 CEST | Direct test started: group admin metadata convergence | Files inspected or touched: `test/features/groups/integration/group_admin_metadata_convergence_test.dart`, `lib/features/groups/application/group_message_listener.dart` | Command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Decision/blocker: added A/B/C/D late invitee name/description catch-up integration regression with no avatar/media assertions | Next action: triage integration result.
- 2026-06-02 17:44:40 CEST | Direct test finished: accept pending invite use case | Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: passed; failed-first-drain catch-up, equal-timestamp repair, and Session 01 accept-settlement regressions pass together | Next action: run required integration metadata convergence test path.
- 2026-06-02 17:42:20 CEST | Production owner file touched / direct test rerun started | Files inspected or touched: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: patched equal-version metadata stale handling to allow signed snapshot name/description repair only when local visible fields differ | Next action: verify accept use-case direct suite.
- 2026-06-02 17:41:45 CEST | Direct test rerun finished: accept pending invite use case after clock fix | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: failed only `GCA-103 equal timestamp metadata replay repairs stale invite snapshot`; failed-first-drain catch-up passed. Root cause is session-owned listener stale-metadata equality handling that can cursor-commit a valid replay while D remains on old name/description. | Next action: patch `group_message_listener.dart` to allow equal-timestamp visible metadata repair, then rerun direct test.
- 2026-06-02 17:41:20 CEST | Direct test rerun started: accept pending invite use case after clock fix | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: new regressions now use current-relative invite timestamps | Next action: triage actual metadata replay result.
- 2026-06-02 17:40:58 CEST | Direct test rerun finished: accept pending invite use case | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: failed in the two new GCA-103 tests because fixed March 2026 invite timestamps were expired on 2026-06-02; classify as test setup clock issue, not production metadata behavior | Next action: switch new regressions to current-relative invite times and rerun.
- 2026-06-02 17:40:36 CEST | Direct test rerun started: accept pending invite use case | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: corrected `callSignPayload` import after compile-only failure | Next action: triage behavioral result.
- 2026-06-02 17:40:13 CEST | Direct test finished: accept pending invite use case | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: failed at compile because new test helper referenced `callSignPayload` from the wrong import; no production behavior classified yet | Next action: fix helper import/signing call and rerun the same direct test.
- 2026-06-02 17:39:36 CEST | Direct test started: accept pending invite use case | Files inspected or touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Command: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` | Decision/blocker: added failed-first-drain and equal-timestamp metadata catch-up regressions before production code edits | Next action: triage pass/fail and patch only owner seams if needed.
- 2026-06-02 17:35:27 CEST | Owner files inspected / regressions selected | Files inspected or touched: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart` | Command: `git status --short`, targeted `git diff -- ...`, targeted `rg -n ...`, targeted `sed -n ...` on owner files/tests | Decision/blocker: existing dirty owner diff is Session 01 accept-settlement only; listener/drain have no pre-existing diff. Evidence points to focused tests around failed first drain catch-up and equal/close metadata timestamp replay before code changes. | Next action: add focused regressions in existing target test files.
- 2026-06-02 17:33:59 CEST | Executor local pass started / contract read | Files inspected or touched: session plan, execution QA skill | Command: `sed -n '1,260p' Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-02-late-metadata-catchup-plan.md`, `sed -n '261,520p' Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-02-late-metadata-catchup-plan.md`, `sed -n '1,240p' /Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md` | Decision/blocker: Executor scope extracted as name/description late metadata catch-up only; no QA Reviewer role will be performed in this pass | Next action: inspect dirty worktree and primary owner files before adding focused regressions.
- 2026-06-02 17:31:47 CEST | Contract extraction started | Files inspected or touched: session plan, execution QA skill, git status | Command: `sed -n '1,260p' Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-02-late-metadata-catchup-plan.md`, `git status --short` | Decision/blocker: spawned CLI path available via `codex exec`; extracting exact scope/tests/gates before coding | Next action: record extracted contract and spawn Executor.
- 2026-06-02 17:31:47 CEST | Contract extracted | Files inspected or touched: session plan | Command: none | Decision/blocker: scope is name/description metadata catch-up only after failed first accepted-inbox drain, delivered-but-unapplied replay, timestamp boundary, and automatic catch-up without repeated Accept; direct tests are `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` and `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`; required named gate is `./scripts/run_test_gates.sh groups` with focused rerun/classification if broad instability recurs; non-goals are avatar bytes/SHA, media ACL/download, relay/backend, simulator harnesses, broad UI, and unrelated dirty worktree changes | Next action: spawn Executor agent.
- 2026-06-02 17:32:15 CEST | Executor spawned/running | Files inspected or touched: session plan | Command: `codex exec -m gpt-5.5 -c reasoning_effort="xhigh" -C /Users/I560101/Project-Sat/mknoon-2/flutter_app -a never -s danger-full-access` | Decision/blocker: Executor must add focused regressions first where feasible, stay inside owner files, preserve dirty worktree, run direct tests and groups gate or classify broad instability | Next action: wait for Executor result.
- 2026-06-02 17:32:51 CEST | Executor spawn retry needed | Files inspected or touched: session plan | Command: previous `codex exec ... -a never -s danger-full-access` | Decision/blocker: spawn command failed before child materialized because approval/sandbox flags must be passed before the `exec` subcommand | Next action: rerun Executor spawn with corrected top-level CLI flags.

## Real Scope

Prove and, if needed, fix User D's convergence from the send-time invite
snapshot to User C's post-invite metadata after D accepts. This session owns
name/description metadata only:

- D starts from an older invite snapshot such as `test 2` / `222`;
- C stores a newer authoritative metadata update such as `test 3` / `333`
  after inviting D but before D accepts;
- D's first accepted-inbox drain may fail with a sustained/non-transient
  relay/inbox error;
- later automatic catch-up, startup/resume catch-up, or explicit group inbox
  drain converges D to `test 3` / `333` without another Accept tap;
- delivered but unapplied metadata replay and close/skewed add-D/edit/accept
  timestamps must not leave D permanently stale.

This session intentionally excludes D-specific avatar bytes/SHA proof, media
ACL changes, and full mobile Scenario 7 simulator closure.

## Closure Bar

Session 02 is complete when focused tests prove that a late invitee can recover
newer authoritative group name/description metadata after a failed first
accepted-inbox drain and after close timestamp boundaries, without requiring
the pending invite to remain actionable. If current evidence shows a
delivered-but-unapplied replay can be silently cursor-committed, this session
must either fix that path or leave a precise `blocked` verdict with the missing
implementation surface.

## Source Of Truth

- Source doc:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- Breakdown:
  `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery-session-breakdown.md`
- Session 01 plan and closure ledger for accepted-invite settlement dependency.
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests win over prose when they disagree.

## Session Classification

`implementation-ready`

The breakdown classified this session as `evidence-gated`. Local planning
evidence shows code/test work is needed or at least must be validated through
new focused tests, so execution should proceed as implementation-ready while
staying inside the metadata catch-up scope.

## Exact Problem Statement

After Session 01, D no longer presses Accept again to recover. The remaining
metadata risk is that D's local group is materialized from the invite's
send-time config, while the authoritative post-invite metadata update may be
missed during the first accepted-inbox drain or may be delivered but treated as
pre-join, stale, invalid, or otherwise unapplied. If that happens and the cursor
is advanced, D can keep seeing `test 2` / `222` as the settled group identity.

## Files And Repos To Inspect Next

Primary owner files:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`

Secondary files only if required by evidence:

- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- startup/resume catch-up callers that already invoke group offline inbox drain

Do not touch avatar storage/download or media ACL code in this session.

## Existing Tests Covering This Area

- `accept_pending_group_invite_use_case_test.dart` already covers accepted
  invite materialization, cursor drain behavior, and replay of post-add group
  messages.
- `group_admin_metadata_convergence_test.dart` already has helpers for
  authoritative metadata replay and A/B/C promoted-admin metadata convergence.
- Existing Session 01 tests now prove repeated Accept is no longer the recovery
  trigger.

Missing coverage:

- no focused test proves D converges from an older invite snapshot to C's newer
  metadata after the first accepted-inbox drain fails;
- no focused test proves close/equal/skewed add-D/edit/accept timestamps do not
  classify a valid post-invite metadata update as permanently stale;
- no focused test proves delivered-but-unapplied metadata replay is retried or
  otherwise recovered instead of silently cursor-committed as success.

## Regression/Tests To Add First

Add focused tests before production-code edits where feasible:

- application test: accepted-inbox drain fails with persistent
  `RELAY_UNAVAILABLE`, D stays joined/settled from Session 01, later
  `drainGroupOfflineInboxForGroup` or the automatic catch-up path replays C's
  authoritative `group_metadata_updated` event and D's group becomes
  `test 3` / `333`;
- integration test: extend or complement `group_admin_metadata_convergence_test`
  with A/B/C/D setup where C invites D, C updates metadata after invite, D
  accepts, and host-side integration verifies D converges to the latest name
  and description after catch-up;
- boundary test: post-invite metadata event and D's materialized `joinedAt` are
  same-millisecond or skewed close enough to exercise pre-join and metadata
  watermark comparisons;
- delivered-but-unapplied test: simulate or assert the listener/drain behavior
  for authoritative metadata replay that is soft-skipped; if current
  architecture cannot distinguish it from success, record the missing
  requeue/resync hook as an implementation-owned gap and fix it in this
  session if owner files are sufficient.

## Step-By-Step Implementation Plan

1. Add the failed-first-drain metadata catch-up regression and make it red or
   document why current code already passes.
2. Add the timestamp boundary regression around add-D, edit, and accept.
3. Inspect delivered-but-unapplied metadata replay paths in
   `group_message_listener.dart` and `drain_group_offline_inbox_use_case.dart`.
   If a valid authoritative metadata replay can return success without applying
   and still commit the cursor, add a narrow recovery hook such as marking the
   replay as not safely applied, forcing current-config resync, or avoiding
   cursor advancement for that replay class.
4. If first-drain failure lacks automatic retry after Session 01 settlement,
   wire the existing startup/resume/group-inbox catch-up path so D can retry
   without an Accept tap.
5. Keep Session 01 settlement behavior intact: no stale pending invite action,
   no duplicate joined timeline/replay output.
6. Run direct tests and the relevant gate commands.

## Risks And Edge Cases

- Cursor advancement after soft metadata skips can hide the only replay of
  `test 3`; tests must distinguish thrown drain failure from normal skip.
- A valid post-invite update may have close/equal timestamps compared with D's
  local `joinedAt` and invite metadata watermark.
- A stale invite snapshot is valid initial state but must not become final
  settled identity when newer authoritative metadata is available.
- Broad fixes to relay retention, media bytes, or simulator harnesses would be
  scope drift.
- The worktree is dirty; preserve unrelated existing changes.

## Device/Relay Proof Profile

Profile: `host-only integration for Session 02`.

Rationale: this session targets Dart-side invite materialization, durable
offline replay, metadata listener watermarks, and startup/resume catch-up seams
that can be proven with host application and integration tests. Final
multi-device/mobile visible Scenario 7 proof remains Session 04. No live device
IDs are required in this session unless execution decides to touch simulator
harnesses, which would be scope drift by default.

Live availability check required for this session: none.

## Exact Tests And Gates To Run

Direct tests:

```bash
flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart
```

Run any new focused test file by exact path if execution creates one.

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

If execution touches startup/resume plumbing outside group-local drain
orchestration, also run the gate selected from
`Test-Flight-Improv/test-gate-definitions.md`, likely:

```bash
./scripts/run_test_gates.sh transport
```

## Known-Failure Interpretation

Session 01 recorded a broad `groups` gate instability: the full gate failed
twice, while the reported/focused slices `group_messaging_smoke_test.dart` and
`ML-004` passed directly. For Session 02, direct tests and newly added
metadata-convergence integration tests are the primary regression evidence. If
the broad groups gate fails again, rerun the reported failing slice directly
and classify whether it is metadata-owned before accepting or blocking.

## Done Criteria

- D converges from the old invite snapshot to latest name/description after a
  failed first accepted-inbox drain and later catch-up.
- D does not need a repeated Accept tap to trigger metadata recovery.
- Close/equal/skewed add-D/edit/accept timestamps do not strand D on stale
  metadata.
- Delivered-but-unapplied authoritative metadata replay is either fixed or
  precisely blocked with an owner-file gap recorded.
- Session 01 invite-settlement tests still pass.
- Direct metadata tests pass, and the groups gate is run or a concrete
  non-session-owned gate blocker is recorded.

## Scope Guard

Do not change group admin permission policy, invite authorization policy, group
key design, relay retention, avatar byte entitlement/download, media ACLs, or
mobile simulator harnesses in this session. Do not claim Scenario 7 full
closure; Session 04 owns that.

## Accepted Differences / Intentionally Out Of Scope

- Avatar metadata/bytes may still diverge after this session; Session 03 owns
  D-specific avatar byte/SHA convergence.
- Final pending invite card, All row, details header, screenshot, and simulator
  proof remain Session 04.
- Relay/backend TTL/cap changes remain out of scope unless current tests prove
  a concrete relay-owned failure inside the normal retention window.

## Dependency Impact

Session 03 depends on Session 02's metadata convergence path so avatar byte
proof can run after D has the latest avatar metadata. Session 04 depends on this
session for full Scenario 7 acceptance evidence.

## Reviewer Findings

- Structural blockers: none.
- Required gate: `./scripts/run_test_gates.sh groups`, with focused direct
  reruns if broad gate instability recurs.
- Device proof: host-only integration is sufficient for Session 02 because
  Session 04 owns final mobile simulator proof.
- Scope risk: delivered-but-unapplied replay may reveal a real
  implementation-owned gap; keep that gap inside listener/drain/current-config
  recovery owner files rather than widening to relay/backend.

## Arbiter Decision

The plan is execution-ready for Session `02-late-metadata-catchup`. It is
allowed to implement code and tests if evidence shows metadata catch-up is
missing, but it must remain limited to name/description metadata replay,
watermark, cursor, and automatic catch-up behavior. It must not close avatar or
full Scenario 7 simulator requirements.

## QA Reviewer Findings

- 2026-06-02 17:59:07 CEST | Fresh QA review completed | Scoped files inspected: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/group_admin_metadata_convergence_test.dart`; Session 01 dependency diff inspected in `lib/features/groups/application/accept_pending_group_invite_use_case.dart` and the shared application test. Blocking findings: none.
- Correctness: the listener now passes parsed metadata into the stale guard and only reprocesses an equal-watermark metadata replay when the signed snapshot would repair visible name/description fields. The existing state-hash, signed-transition/actor verification, membership authorization, and authoritative config application still run before the drain can commit the inbox cursor. This stays inside Session 02 metadata scope and does not touch avatar bytes, media ACLs, relay/backend, simulator harnesses, or UI.
- Regression coverage: the application suite covers Session 01 invite settlement, failed first accepted-inbox drain followed by later metadata catch-up without another Accept tap, and equal-timestamp stale invite snapshot repair with cursor advancement after successful application. The integration suite adds A/B/C/D signed replay coverage for D converging from `test 2` / `222` to `test 3` / `333`.
- Verification rerun by QA: `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart` passed; `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart` passed; `git diff --check -- lib/features/groups/application/group_message_listener.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/group_admin_metadata_convergence_test.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart` passed.
- Gate classification: executor ran `./scripts/run_test_gates.sh groups` and it exited 1 in broad smoke coverage; the reported focused slice `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-003 fake-network randomized key epoch monotonicity keeps active epoch"` passed. Given the scoped direct tests pass and the focused failing slice passed, this remains a non-session-owned broad gate instability.

## Final Execution Verdict

Status: `accepted_with_explicit_follow_up`

Session 02 is accepted for name/description metadata catch-up after a failed
first accepted-inbox drain, equal timestamp stale invite snapshot repair, and
delivered-but-unapplied cursor behavior. The explicit follow-up is the broad
`groups` gate instability described above; it is not a Session 02 blocker.
Avatar byte convergence, media ACL proof, and full Scenario 7 simulator closure
remain out of scope for Session 03/04.
