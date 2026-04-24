# Session 2 Plan - Freeze post-dissolve reactions across send, remove, receive, and group-conversation entry points

## Final verdict

- `implementation-ready`

## Real scope

- Add dissolved-state rejection to `sendGroupReaction(...)` so a dissolved
  group cannot accept a new optimistic or published reaction mutation.
- Add the same dissolved-state rejection to `removeGroupReaction(...)` so a
  dissolved group cannot silently mutate stored reactions after the final
  dissolve state.
- Reject incoming live or replayed reaction payloads at or after the stored
  dissolve cutoff while still allowing a pre-dissolve reaction timestamp that
  arrives later to land truthfully.
- Remove group-conversation reaction-entry affordances for dissolved groups
  without breaking read-only reaction inspection on existing chips.
- Prove the blocked reaction contract for both discussion and announcement
  groups without widening into feed-thread projection or delete-after-dissolve
  UX.

## Closure bar

- `sendGroupReaction(...)` returns a predictable blocked result for dissolved
  groups and does not publish or persist a reaction.
- `removeGroupReaction(...)` returns a predictable blocked result for
  dissolved groups and does not publish or remove stored reactions.
- `handleIncomingGroupReaction(...)` ignores reaction add/remove payloads whose
  timestamps are at or after the stored dissolve cutoff and continues to allow
  pre-dissolve timestamps that arrive late.
- `GroupConversationWired` stops exposing reaction-entry callbacks when the
  visible group is dissolved, and a stale callback path cannot leave behind a
  fake accepted reaction if the use case reports `groupDissolved`.
- Existing active-group reaction behavior stays intact for discussion and
  announcement groups before any dissolve occurs.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- Governing product/problem docs:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
  - `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- Regression and gate docs:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Primary code/tests:
  - `lib/features/groups/application/send_group_reaction_use_case.dart`
  - `lib/features/groups/application/remove_group_reaction_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`

On disagreement:

- current code and tests beat older prose
- `test-gate-definitions.md` is the source of truth for named gates
- the incoming reaction cutoff should mirror the already-landed
  `handle_incoming_group_message_use_case.dart` dissolved cutoff semantics
  instead of inventing a new timeline rule

## Session classification

- `implementation-ready`

## Exact problem statement

- Report `72` already proved that full-message send paths and the full
  conversation composer are frozen after dissolve, but reaction paths are not.
- `send_group_reaction_use_case.dart` and
  `remove_group_reaction_use_case.dart` currently validate only group
  existence, membership, and target-message presence, so a dissolved group can
  still accept new reaction publish attempts locally.
- `handle_incoming_group_reaction_use_case.dart` currently binds payload sender
  to transport sender, but it never compares the reaction timestamp to the
  stored dissolve cutoff, so replay or late live delivery can still mutate
  reactions after the group has ended.
- `GroupConversationWired` computes `_canWrite` correctly for dissolved groups
  yet still passes `onReactionSelected` whenever `reactionRepo` exists, leaving
  the long-press reaction bar reachable even when the group is read-only.
- This session must close those reaction-specific frozen-state gaps without yet
  taking on feed projection or the local-delete cleanup contract.

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/send_group_reaction_use_case.dart`
  - `lib/features/groups/application/remove_group_reaction_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Tests:
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`

## Existing tests covering this area

- `send_group_reaction_use_case_test.dart`
  covers active-group success, non-member rejection, unknown message/group,
  publish failure, and durable replay staging, but it does not cover dissolved
  groups.
- `remove_group_reaction_use_case_test.dart`
  covers active-group success, idempotent absent reaction removal, non-member
  rejection, and durable replay staging, but it does not cover dissolved
  groups.
- `handle_incoming_group_reaction_use_case_test.dart`
  covers parse failure, sender mismatch, and ordinary add/remove behavior, but
  it does not cover the dissolve cutoff rule.
- `group_conversation_wired_test.dart`
  already proves dissolved groups are read-only for send/compose controls and
  proves reaction inspection on existing chips, but it does not prove that the
  long-press reaction entry bar disappears for dissolved groups.
- `announcement_happy_path_test.dart`
  already proves announcement readers can react before dissolve.
- `group_reaction_roundtrip_test.dart`
  already proves live active-group reaction roundtrip.

## Regression/tests to add first

- Add a chat-group dissolved send-reaction regression and an announcement-group
  dissolved send-reaction regression.
- Add a dissolved remove-reaction regression that proves stored reactions stay
  untouched.
- Add incoming reaction regressions for:
  - add at or after dissolve cutoff is ignored
  - remove at or after dissolve cutoff is ignored
  - a pre-dissolve timestamp that arrives after dissolve is still accepted
- Add a widget regression that proves dissolved group conversation hides the
  long-press reaction bar while keeping read-only history visible.
- Add one active-group widget regression that proves the reaction bar still
  appears when reaction mutation deps are present so the new dissolved guard is
  meaningful.

## Step-by-step implementation plan

1. Add the direct regression coverage listed above.
2. Introduce a dedicated `groupDissolved` blocked result on send/remove
   reaction use cases rather than overloading `notMember` or `publishFailed`.
3. Reject dissolved groups early in
   `send_group_reaction_use_case.dart` and
   `remove_group_reaction_use_case.dart` before any publish or local mutation.
4. Mirror the existing incoming-message dissolved cutoff rule inside
   `handle_incoming_group_reaction_use_case.dart` by parsing the reaction
   timestamp and ignoring payloads at or after `group.dissolvedAt`.
5. Tighten `GroupConversationWired` so `onReactionSelected` is exposed only
   when the group is writable and all reaction-mutation deps exist.
6. Add a stale-callback safeguard in `_onReactionSelected(...)` so a
   `groupDissolved` result reverts the optimistic local change, refreshes the
   group, and shows the existing dissolved snackbar.
7. Run the direct suites, the targeted integration suites, and the `groups`
   gate.

## Risks and edge cases

- Incoming reaction cutoff logic must not drop a valid pre-dissolve reaction
  that simply replays late from offline inbox recovery.
- The UI change must preserve reaction inspection via existing chips
  (`onReactionTap`) even when new reaction entry is disabled.
- The optimistic reaction path currently mutates `_reactions` first; the stale
  callback path must restore truthful local state on a `groupDissolved`
  rejection instead of leaving a ghost chip behind.
- Adding a new result enum must not accidentally widen Session `3` feed work;
  feed-specific stale entry paths stay for Session `3` unless direct evidence
  shows this session cannot compile or verify cleanly without a narrow update.

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- Targeted integration tests:
  - `flutter test test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups`

## Known-failure interpretation

- The worktree is already dirty in unrelated notification/push files. Treat
  failures outside the touched reaction/frozen-state seam as pre-existing
  unless the direct reaction suites or the `groups` gate show a regression in
  touched files.
- If the full `groups` gate fails in untouched feed/delete-after-dissolve
  areas, record that honestly instead of broadening Session `2`.

## Done criteria

- Dissolved groups return a dedicated blocked result for reaction add/remove.
- No reaction publish or local reaction mutation happens after dissolve.
- Incoming live/replayed reaction payloads at or after the dissolve cutoff are
  ignored.
- Late-arriving pre-dissolve reaction payloads still land.
- Dissolved group conversation keeps reaction inspection but not reaction entry.
- Discussion and announcement reaction-freeze regressions pass.
- The `groups` gate passes, or any unrelated pre-existing failure is
  documented honestly.

## Scope guard

- Do not propagate dissolved state into feed thread models in this session.
- Do not add the dissolved local-delete affordance in this session.
- Do not reopen dissolve authority logic from Session `1` unless a new test
  proves this session cannot verify without it.
- Do not redesign the broader reaction UX or emoji picker behavior.

## Accepted differences / intentionally out of scope

- Feed-surface reaction affordance cleanup stays in Session `3`.
- Local-delete-after-dissolve UX stays in Session `4`.
- Stable audit/matrix doc refresh stays in Session `5`.

## Dependency impact

- Session `3` depends on this session to give feed projection one stable
  reaction-freeze contract.
- Session `4` depends on this session so the later cleanup UX is not layered on
  top of a still-mutable dissolved conversation surface.

## Structural blockers remaining

- None at planning time.

## Incremental details intentionally deferred

- Whether extra resume/offline replay integration coverage is needed beyond the
  direct cutoff tests can be decided after the targeted suites and `groups`
  gate.

## Accepted differences intentionally left unchanged

- Existing reaction inspection sheets remain available on already-stored chips
  because they are read-only and do not violate the frozen-state contract.

## Exact docs/files used as evidence

- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/remove_group_reaction_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

## Why the plan is safe to implement now

- The gap is narrow and already isolated in one reaction family across
  use-case, listener, and conversation-entry seams.
- The incoming cutoff rule can reuse an existing repo-owned pattern from
  `handle_incoming_group_message_use_case.dart` instead of inventing a new
  timestamp contract.
- The required validation is direct, local, and scoped tightly enough to stop
  before the later feed and cleanup sessions.
