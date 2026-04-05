# 63 Session 3 Plan: Expose Group Backlog Retention Outcomes In UI

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- surface one truthful retention-boundary notice in the shipped group
  conversation UI when offline recovery expired older backlog
- distinguish fully expired backlog from mixed-window recovery where newer
  messages were restored but older ones expired
- add a shorter retention status in the group list so users can see the
  recovery outcome before opening the thread
- refresh the relevant wired group surfaces on resume or incoming prop updates
  so persisted retention-state changes are visible without requiring a cold
  restart
- add focused presentation/widget regressions for the new copy and refresh
  behavior

Out of scope for this session:

- changing replay filtering or retention-state persistence logic
- relay protocol changes or server-side pruning
- matrix/doc closure work
- notification payload changes unless existing route entry points require a
  minimal compile-shape adjustment

### Closure bar

Session `3` is done only when:

- fully expired backlog shows a clear conversation-level outcome instead of the
  misleading generic empty-state copy
- mixed-window recovery shows a truthful “recent messages recovered, older
  backlog expired” outcome
- the group list exposes the same retention contract in shorter form
- the wired conversation and list surfaces can refresh persisted retention
  state after resume or widget-driven group updates
- direct presentation tests and the required named gate prove the shipped copy
  without reopening replay-path correctness work

### Source of truth

- active session contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- Session `2` replay contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md`
- product/problem doc:
  `Test-Flight-Improv/63-group-message-retention-boundary.md`
- retention policy seam:
  `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- conversation UI seams:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- group list UI seams:
  `lib/features/groups/presentation/screens/group_list_wired.dart`
  `lib/features/groups/presentation/screens/group_list_screen.dart`
  `lib/features/groups/presentation/widgets/group_card.dart`

On disagreement, landed replay behavior from Session `2` and current UI tests
beat stale prose.

### Session classification

- `implementation-ready`

### Exact problem statement

The repo now truthfully filters expired group backlog during replay, but the
shipped UI still has no way to tell the user what happened. Fully expired
recovery still falls back to generic “No messages yet” copy, and mixed-window
recovery looks the same as a complete catch-up even though older backlog was
discarded.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`

Current direct-test seams:

- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

### Existing tests covering this area

- `group_conversation_screen_test.dart` already proves read-only banners,
  loading/empty states, and dissolved-group copy, so it is the right place for
  new backlog-retention banner and empty-state assertions
- `group_conversation_wired_test.dart` already proves repo refresh after info
  navigation and role-based write restrictions, so it can absorb retention
  refresh assertions if needed
- `group_list_screen_test.dart` already proves empty/loading states and pending
  invite expiry UI, so it can cover the new retention summary line
- `group_list_wired_test.dart` already proves repo reload after message-driven
  refreshes, so it can absorb minimal retained-state reload proof if required

Missing today:

- no shared UI helper that translates persisted retention fields into one
  shipped contract
- no conversation banner or empty-state override for expired backlog
- no group-list indication that older backlog expired
- no test proving persisted retention-state refresh after resume-aware UI
  reloads

### Regression/tests to add first

- add conversation-screen tests first for:
  - fully expired backlog banner plus empty-state override
  - mixed-window recovery banner while retained messages remain visible
- add group-list screen tests for:
  - fully expired list summary
  - mixed-window list summary alongside the retained latest message
- add or extend wired tests only if the implementation needs refresh-specific
  proof beyond the screen-level assertions

### Step-by-step implementation plan

1. Add one small shared presentation helper that maps the persisted retention
   fields to user-visible expired versus mixed-window copy using the Session `1`
   7-day policy constant.
2. Update `GroupConversationScreen` to render a retention banner and truthful
   empty-state copy when backlog expired.
3. Update `GroupCard` and `GroupListScreen` to show a shorter retention status
   line for affected groups.
4. Teach `GroupConversationWired` and `GroupListWired` to refresh their visible
   group state on resume, and ensure conversation widget snapshot syncing
   includes the new retention fields.
5. Add the focused presentation/widget tests above, then run the direct suites
   and required named gate.
6. Stop and tighten scope if the implementation starts needing replay-path
   changes, notification-payload changes, or doc/matrix closure work.

### Risks and edge cases

- do not show a retention warning when `lastBacklogExpiredAt` is null
- do not reuse the read-only banner seam for retention state; backlog expiry is
  informational, not a send-permission change
- avoid implying that the entire conversation history is gone when only older
  missed backlog expired
- make sure widget refresh logic does not introduce unnecessary loops or broad
  rebuild churn

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_list_screen_test.dart`
- `flutter test test/features/groups/presentation/group_list_wired_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- any failure in the conversation or list presentation suites is a Session `3`
  blocker
- any `groups` gate failure touching group presentation, refresh behavior, or
  compile-shape fallout from the new helper is a session regression and must be
  fixed here

### Done criteria

- conversation UI shows truthful expired or mixed-window recovery copy
- generic empty-state copy no longer hides fully expired backlog
- group list shows the same contract in shorter form
- refresh wiring is sufficient for persisted retention-state changes to become
  visible in normal resumed app usage
- the direct presentation tests above pass
- the required named gate is run

### Scope guard

- do not change replay filtering or database persistence in this session
- do not add new retention columns, migrations, or relay request parameters
- do not broaden into notification routing or final matrix/doc updates
- do not invent additional retention durations or per-group policy variants

### Accepted differences / intentionally out of scope

- Session `3` only explains the already-landed replay behavior; it does not
  change what gets retained
- notification-entry behavior remains whatever the existing route open already
  shows once the conversation screen is opened
- final `UX-008` closure remains Session `4` work

### Dependency impact

- Session `4` depends on this session so maintained docs can point at truthful
  shipped UI rather than replay-only behavior
- if this session lands a smaller surface than planned, the breakdown and final
  closure pass must reflect the remaining visible-UX gap honestly

## Structural blockers remaining

- `none`

## Incremental details intentionally deferred

- whether later product work wants richer timestamps or “learn more” copy for
  the retention boundary
- whether future notification surfaces should mirror the same summary inline

## Accepted differences intentionally left unchanged

- no replay-path or retention-policy changes
- no doc or matrix closure work

## Exact docs/files used as evidence

- `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md`
- `Test-Flight-Improv/63-group-message-retention-boundary.md`
- `lib/features/groups/domain/models/group_backlog_retention_policy.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because Session `2` already landed the
persisted retention-state fields and proved the replay contract directly. This
session stays on presentation seams, uses one shared helper so the list and
conversation surfaces cannot silently diverge, and avoids reopening the replay
pipeline or final doc closure work.
