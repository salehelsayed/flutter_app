# 62 Session 2 Plan: Ship Dissolve Propagation and Enforcement

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add one admin-only dissolve use case that publishes a `group_dissolved`
  system event, attempts relay inbox fallback for offline members, records the
  local group as dissolved, persists a readable timeline event, and leaves the
  live topic without deleting history
- teach `GroupMessageListener` to authenticate and apply `group_dissolved` on
  both live and replay paths
- reject post-dissolve sends and skip dissolved groups during startup/recovery
  rejoin
- add direct application and integration regressions for duplicate handling,
  offline replay convergence, send rejection, and rejoin skipping

Out of scope for this session:

- visible dissolve affordances in the shipped UI
- maintained audit or matrix doc updates
- visual dissolved badges or read-only banner copy refinements

### Closure bar

Session `2` is done only when:

- an admin can dissolve a stored group without deleting local history
- the listener applies `group_dissolved` exactly once and persists a readable
  timeline event for recipients
- replayed dissolve envelopes converge to the same stored final state as live
  delivery
- `sendGroupMessage(...)` and incoming-message handling reject post-dissolve
  traffic predictably
- `rejoinGroupTopics(...)` does not resubscribe dissolved groups

### Source of truth

- active session contract:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- current listener seam:
  `lib/features/groups/application/group_message_listener.dart`
- current send seam:
  `lib/features/groups/application/send_group_message_use_case.dart`
- current restart seam:
  `lib/features/groups/application/rejoin_group_topics_use_case.dart`

### Exact problem statement

The repo can now store dissolved state, but nothing produces or enforces it.
Session `2` must turn that persisted state into a real transport and replay
contract so live peers, offline peers, send attempts, and restart recovery all
agree that a dissolved group is permanently read-only.

### Files and repos to inspect next

Production files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_timeline_message.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`

Direct tests:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

### Step-by-step implementation plan

1. Add the dissolve use case plus timeline-text builder and make it update the
   local group row instead of deleting it.
2. Extend `GroupMessageListener` with authenticated `group_dissolved` handling,
   stale/duplicate rejection, replay parity, and topic leave behavior that
   preserves local history.
3. Reject post-dissolve sends in `sendGroupMessage(...)`, reject incoming
   messages at or after the dissolve cutoff, and skip dissolved groups in
   `rejoinGroupTopics(...)`.
4. Add targeted tests for the use case, live and replay listener handling,
   send rejection, rejoin skipping, and one multi-user convergence path.

### Risks and edge cases

- do not reuse `leaveGroup(...)`; it deletes the local group row and changes
  the product meaning from dissolve into personal exit
- keep duplicate or stale `group_dissolved` delivery idempotent so it does not
  emit multiple timeline rows or repeated leave calls
- preserve pre-dissolve messages while rejecting messages at or after the
  dissolve cutoff
- keep admin-only authorization explicit on both local use case and inbound
  system-event handling

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/dissolve_group_use_case_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart`

Required named gates:

- defer `./scripts/run_test_gates.sh groups` until the UI session lands, unless
  a session-2 regression forces earlier broader verification

### Done criteria

- dissolve is now a truthful network and replay contract, not only stored state
- session `3` can focus on making the already-landed behavior visible in the UI

### Scope guard

- do not start visible UI work until the listener/send/rejoin contract is green
- do not update maintained docs until sessions `2` and `3` both land
