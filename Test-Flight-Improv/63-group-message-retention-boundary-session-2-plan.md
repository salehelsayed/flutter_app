# 63 Session 2 Plan: Enforce Group Backlog Retention During Replay

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- apply the repo-owned `groupBacklogRetentionWindow` during cursor-based group
  inbox drain so replayed backlog messages older than the cutoff are treated as
  expired
- persist the replay outcome into the Session `1` storage contract by updating
  `lastBacklogExpiredAt` and `lastBacklogRetainedAt` on the affected group
- preserve system-envelope replay for membership, removal, and dissolve events
  even when they are older than the message-retention cutoff
- add direct drain and resume-recovery regressions for within-window,
  beyond-window, mixed-window, and repeated-retry cases

Out of scope for this session:

- any user-facing expired-backlog copy or banner
- server-side pruning or relay protocol changes
- changing live pubsub delivery semantics
- matrix or architecture-doc closure work

### Closure bar

Session `2` is done only when:

- replayed non-system group backlog older than the retention cutoff no longer
  persists locally
- replayed non-system backlog inside the cutoff still lands normally
- mixed replay windows keep newer retained messages while older expired ones do
  not appear
- repeated drain/retry attempts do not resurrect backlog the app already
  treated as expired
- authoritative replayed system envelopes still converge local membership state
  correctly
- direct tests and named gates prove the replay contract without needing UI
  assertions yet

### Source of truth

- active session contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- Session `1` storage contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md`
- product/problem doc:
  `Test-Flight-Improv/63-group-message-retention-boundary.md`
- named gate contract:
  `Test-Flight-Improv/test-gate-definitions.md`
- retention policy seam:
  `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- replay seam:
  `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- current direct replay coverage:
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  `test/features/groups/integration/group_resume_recovery_test.dart`

On disagreement, current replay code and tests beat stale prose.

### Session classification

- `implementation-ready`

### Exact problem statement

The repo now has a persisted retention contract, but `drainGroupOfflineInbox`
still replays every non-empty cursor page message regardless of age. That means
`UX-008` is still false in practice: long-offline backlog never expires in the
app-owned recovery path, and the app cannot tell later UI whether the user
recovered everything or crossed the retention boundary.

### Files and repos to inspect next

Production files:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- `lib/features/groups/domain/models/group_model.dart`

Current direct-test seams:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Related correctness seams to keep intact:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`

### Existing tests covering this area

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  already proves cursor paging, dedupe, self-removal stop conditions, and the
  remove-vs-send cutoff across later cursor pages
- `test/features/groups/integration/group_resume_recovery_test.dart` already
  proves multi-page backlog replay, no-dup cursor continuation, and partition
  catch-up in cursor order
- `./scripts/run_test_gates.sh groups` already exercises the broader group
  replay and recovery path after direct suites pass

Missing today:

- no direct test that treats old replayed backlog as expired
- no persisted proof that mixed old/new backlog updates the new retention-state
  fields truthfully
- no integration proof that repeated drain attempts still keep expired backlog
  unavailable

### Regression/tests to add first

- add drain-use-case regressions first for:
  - within-window backlog stays replayable
  - beyond-window backlog is dropped and records `lastBacklogExpiredAt`
  - mixed-window replay keeps newer messages, drops older ones, and records
    both retention timestamps
  - repeated drains do not reinsert already-expired backlog
- add one integration regression in
  `test/features/groups/integration/group_resume_recovery_test.dart` for a
  long-offline member with old and new inbox pages around the cutoff

### Step-by-step implementation plan

1. Add the new direct replay tests above using fixed timestamps around
   `groupBacklogRetentionCutoff(...)`.
2. Teach `_drainGroupInbox(...)` to parse replay timestamps, classify
   non-system backlog against the retention cutoff, and skip persistence for
   expired replay messages.
3. Keep replayed `{"__sys": ...}` envelopes exempt from the message-retention
   cutoff so membership and dissolve convergence do not regress.
4. Track the latest expired replay timestamp and latest retained replay
   timestamp seen during the drain, then persist that outcome back through
   `groupRepo.updateGroup(...)`.
5. Add the integration regression for mixed long-offline recovery and rerun the
   direct suites plus required gates.
6. Stop and tighten the plan if the implementation starts requiring UI copy,
   relay protocol changes, or live-path message filtering.

### Risks and edge cases

- do not drop replayed system envelopes older than the message-retention window
  or group membership can drift permanently
- do not stop cursor continuation just because one page contains expired
  messages; later pages may still contain retained backlog
- preserve messageId dedupe so retained messages do not duplicate across
  repeated drains
- be careful with invalid or missing timestamps; default toward retaining the
  message rather than silently expiring unparseable payloads

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

### Known-failure interpretation

- if `baseline` still fails in an unchanged non-group harness outside this
  session’s write scope, record the exact file/message and classify it as
  unchanged pre-existing noise only when the failure is identical
- any failure in the direct drain or resume-recovery suites is a Session `2`
  blocker
- any `groups` gate failure in replay, drain, member-removal, or duplicate
  handling is a session regression and must be fixed here

### Done criteria

- within-window replay still saves missed messages
- beyond-window replay does not save expired backlog
- mixed replay windows persist only the retained messages and record truthful
  retention-state fields
- repeated drains do not reinsert expired backlog
- replayed system envelopes still apply membership/dissolve convergence
- the direct tests above pass
- required named gates are run and any unchanged known failures are recorded

### Scope guard

- do not add banners, snackbars, placeholders, or any other visible UX in this
  session
- do not change `handleIncomingGroupMessage(...)` for live pubsub traffic
  unless compile-shape fallout forces a minimal adjustment
- do not add relay request parameters or server-side retention enforcement
- do not update maintained matrix or architecture docs in this session

### Accepted differences / intentionally out of scope

- system replay remains correctness-first and bypasses the message-retention
  cutoff
- relay storage may still contain old backlog; this session only changes the
  app-owned replay behavior
- final user-facing explanation of expired versus mixed recovery remains Session
  `3` work

### Dependency impact

- Session `3` depends on this session to make `lastBacklogExpiredAt` and
  `lastBacklogRetainedAt` reflect real replay outcomes
- Session `4` should not close `UX-008` until this replay contract is landed
  and revalidated

## Structural blockers remaining

- `none`

## Incremental details intentionally deferred

- the exact copy later shown for fully expired versus mixed-window recovery
- whether later UI surfaces the retention notice in one screen or multiple

## Accepted differences intentionally left unchanged

- no relay-server pruning work
- no live pubsub retention filtering
- no UI or doc closure work

## Exact docs/files used as evidence

- `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- `Test-Flight-Improv/63-group-message-retention-boundary-session-1-plan.md`
- `Test-Flight-Improv/63-group-message-retention-boundary.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because it stays on one coherent seam:
offline group replay. It uses the Session `1` storage contract that already
passed direct tests and both required gates, and it explicitly avoids the two
big ways this slice could sprawl: UI work and server-side retention logic.
