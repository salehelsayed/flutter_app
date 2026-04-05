# 61 Session 3 Plan: Mute Controls and Pending Invite Review UI

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add a user-facing mute or unmute control to an existing joined-group surface
  using the session `1` mute persistence contract
- extend the shipped group list surface to show pending invites that can be
  accepted or declined explicitly
- keep the pending-invite UI truthful for pending, expired, accepted, and
  declined outcomes without silently joining
- refresh the joined group list and pending rows when invite decisions resolve
- add widget and wired regressions for the mute affordance and pending-invite
  accept or decline flow

Out of scope for this session:

- changing the underlying pending invite persistence or acceptance contract
  from session `2`
- audit, matrix, or proposal-doc closure work, which belongs to session `4`

### Closure bar

Session `3` is done only when:

- a joined member can mute and unmute one group from a shipped surface and the
  UI reflects the persisted mute state
- pending invites render in a shipped list surface with explicit accept and
  decline actions instead of hidden auto-join behavior
- accepting a pending invite removes the pending row and refreshes the joined
  groups list with the accepted group
- declining or accepting an expired invite removes the stale row and reports an
  honest outcome to the user
- the targeted presentation tests pass for the new mute and invite-review
  behavior

### Source of truth

- active session contract:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls.md`
- gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- regression strategy:
  `Test-Flight-Improv/14-regression-test-strategy.md`

### Exact problem statement

The repo now has truthful mute persistence and pending invite lifecycle seams,
but the shipped presentation layer still lacks the controls that let members
use them. Session `3` must expose those seams in stable screens so mute and
invite decisions are a real product contract rather than backend-only behavior.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/application/set_group_muted_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/decline_pending_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`

Direct tests:

- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

### Step-by-step implementation plan

1. Add a mute or unmute affordance to the group info screen and wire it to
   `setGroupMuted(...)` with stable feedback and persisted state refresh.
2. Teach `GroupListWired` to load pending invites from the existing pending
   invite repository and subscribe to invite-review refresh streams.
3. Extend `GroupListScreen` with a bounded pending-invite section that exposes
   accept and decline actions plus truthful expired-state presentation.
4. Wire pending invite acceptance and decline actions so they update both the
   pending rows and the joined group list without hidden navigation side
   effects.
5. Add targeted widget and wired regressions for mute toggling, pending invite
   rendering, accept, decline, and accepted-group refresh behavior.

### Risks and edge cases

- avoid double-tap invite decisions by disabling buttons while an action is in
  flight
- keep expired invites clearly non-joinable and make sure their rows disappear
  after the user resolves them
- do not break the existing group-list message refresh path while adding
  pending invite state
- keep group-info back navigation returning mutation state so upstream refresh
  behavior remains intact

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/groups/presentation/group_list_screen_test.dart`
- `flutter test test/features/groups/presentation/group_list_wired_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- the mute toggle and pending invite review UI land with presentation-level
  proof
- accepted invites refresh the joined list without auto-navigation surprises
- the doc-61 session-3 ledger entry can truthfully move out of `pending`

### Scope guard

- do not reopen the session-2 repository or lifecycle contract unless a UI bug
  proves it is incomplete
- do not start matrix and audit doc edits in this session
