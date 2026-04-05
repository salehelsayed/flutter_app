# 62 Session 3 Plan: Expose Dissolve and Dissolved-State UI

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add an admin-only dissolve action with explicit confirmation inside group
  info
- make dissolved groups visibly different across group info, the conversation
  surface, and group-list cards
- switch dissolved conversations to explicit read-only copy rather than
  reusing the announcement-only banner text
- hide leave, metadata editing, add-member, and member-role-management
  affordances once a group is dissolved
- add focused widget and wired regressions that prove the visible contract and
  the dissolve action wiring

Out of scope for this session:

- changes to the already-landed transport or replay contract from session `2`
- maintained audit or matrix doc updates
- broader redesign of group surfaces outside dissolve-specific status and
  affordances

### Closure bar

Session `3` is done only when:

- admins can trigger dissolve from shipped group info with a confirmation step
- group info shows a clear dissolved-state outcome and no longer exposes leave
  or member-management actions afterward
- the group conversation surface shows explicit dissolved read-only copy and
  hides composer affordances
- the group list surface visibly labels dissolved groups instead of relying
  only on timeline text

### Source of truth

- active session contract:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- current group-info wiring:
  `lib/features/groups/presentation/screens/group_info_wired.dart`
- current conversation wiring:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- current pure widgets:
  `lib/features/groups/presentation/screens/group_info_screen.dart`
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  `lib/features/groups/presentation/widgets/group_card.dart`

### Exact problem statement

The dissolve state is now real in storage, listener, send, and recovery seams,
but the shipped UI still behaves like every group is active. Session `3` must
make the admin action discoverable, make the dissolved state visible, and stop
presenting stale leave/edit/member-management controls once a group has ended.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`

Direct tests:

- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_card_bidi_test.dart`

### Step-by-step implementation plan

1. Extend the pure UI widgets with a dissolved status treatment and explicit
   read-only copy while keeping the existing announcement read-only behavior
   unchanged.
2. Wire the admin dissolve confirmation in `GroupInfoWired` using the existing
   session-2 dissolve use case, then refresh local group state after success.
3. Hide leave and admin-management affordances whenever the loaded group is
   dissolved, and show the retained-history status in group info.
4. Add widget and wired tests that prove the admin action, the visible
   dissolved-state contract, and the conversation/group-list read-only UI.

### Risks and edge cases

- keep the announcement read-only contract unchanged while adding a distinct
  dissolved message path
- make sure stale navigation snapshots refresh after the info route returns so
  the conversation reflects the dissolved state immediately
- do not let the dissolve action appear when the group is already dissolved or
  when the viewer is not an admin
- keep message history visible; this session should not reintroduce local group
  deletion semantics

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test test/features/groups/presentation/group_card_bidi_test.dart`

Required named gates:

- defer `./scripts/run_test_gates.sh groups` to session `4` unless a wider UI
  regression forces earlier broader verification

### Done criteria

- dissolve is visible and actionable in the shipped UI rather than hidden in
  lower-layer state only
- session `4` can limit itself to maintained-doc updates and final verification

### Scope guard

- do not change the session-2 transport/replay rules unless a UI regression
  exposes a real bug
- do not update maintained docs until the UI surfaces and direct tests are
  green
