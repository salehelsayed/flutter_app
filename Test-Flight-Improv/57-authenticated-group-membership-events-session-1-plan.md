# 57 Session 1 Plan: Authenticate Repo-Owned Membership System Events in the Listener

## Final verdict

`implementation-ready`

## Real scope

- Add one listener-owned authorization gate for inbound repo-owned membership
  system events so unauthorized add/remove updates are ignored before they
  mutate local state.
- Use trustworthy local admin facts already stored in the group repo instead of
  trusting the inbound `groupConfig` snapshot.
- Apply the same rule to live and replayed listener handling for
  `member_added`, `members_added`, and `member_removed`.
- Add the smallest direct regressions needed to prove unauthorized events are
  ignored while valid admin events still work.
- Update the maintained group architecture/matrix docs so `SC-001` and
  `SC-015` tell the same truthful story without inventing unsupported
  promotion/demotion flows.

## Closure bar

Session `1` is good enough only when all of the following are true:

- inbound non-admin membership system events no longer mutate local member
  state
- those unauthorized events also do not call `group:updateConfig` and do not
  emit misleading system timeline entries
- valid admin-owned `member_added`, `members_added`, and `member_removed`
  events still apply successfully
- replayed listener handling follows the same authorization rule as live
  delivery
- direct listener regressions and one peer-visible membership integration proof
  pass
- `Test-Flight-Improv/09-network-group-messaging.md`,
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, and
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  all close `SC-001` and `SC-015` truthfully for the repo-owned add/remove
  seam

## Source of truth

- Active task docs:
  - `Test-Flight-Improv/57-authenticated-group-membership-events.md`
  - `Test-Flight-Improv/57-authenticated-group-membership-events-session-breakdown.md`
- Governing architecture and matrices:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Regression and gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current seam owners:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/repositories/group_repository.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/shared/fakes/group_test_user.dart`

On disagreement, current code and passing direct tests beat stale prose. This
session must stay scoped to the repo-owned listener seam rather than inventing
new signed-event or validator architecture.

## Exact problem statement

The listener currently applies inbound `member_added`, `members_added`, and
`member_removed` system messages after stale-event checks but without verifying
that the sender is locally known as an authorized admin. That leaves the
repo-owned layer vulnerable to a raw bypass: a non-admin can inject a system
event and the app will currently accept it even though the UI/use-case path
would have blocked the same action.

What must improve:

- unauthorized inbound membership events must be ignored before any state
  mutation or timeline side effect

What must stay true:

- valid authorized add/remove behavior
- duplicate-event and stale-event protections
- existing remove-vs-send cutoff behavior for authorized removal events
- unsupported promotion/demotion flows stay out of scope rather than being
  silently implemented

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/repositories/group_repository.dart`
- Direct tests:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Test harness:
  - `test/shared/fakes/group_test_user.dart`
- Closure docs:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`

## Existing tests covering this area

- `test/features/groups/application/group_message_listener_test.dart` already
  covers valid `member_added`, `members_added`, and `member_removed` handling,
  readable timeline emission, duplicate-event idempotence, and stale-event
  rollback protection.
- `test/features/groups/integration/group_membership_smoke_test.dart` already
  carries the three-user membership convergence surface and is the right place
  for a peer-visible raw bypass regression.
- Current local use-case tests for add/remove prove UI/use-case admin gating,
  but they do not close raw inbound membership-event authorization by
  themselves.

## Regression/tests to add first

- Add listener regressions in
  `test/features/groups/application/group_message_listener_test.dart` for:
  - unauthorized `member_added` is ignored
  - unauthorized `members_added` is ignored
  - unauthorized `member_removed` is ignored
  - replayed unauthorized membership event is also ignored
  - authorized control cases still succeed after the guard lands
- Add one integration regression in
  `test/features/groups/integration/group_membership_smoke_test.dart` where a
  non-admin injects a raw membership system event and peers keep the canonical
  member list unchanged.

## Step-by-step implementation plan

1. Add one small helper in `group_message_listener.dart` that decides whether a
   sender is authorized to apply repo-owned membership system events using
   durable local facts:
   - current group `createdBy`
   - current member role for `senderId`
2. Call that helper before `_handleMemberAdded`, `_handleMembersAdded`, or
   `_handleMemberRemoved` mutate state.
3. If unauthorized:
   - emit one explicit flow event for observability
   - return without saving members, removing members, syncing config, or
     emitting timeline entries
4. Add the listener regressions first so the exact bypass seam is pinned.
5. Add the integration regression proving peers do not converge on forged
   membership state from a non-admin sender.
6. Update the architecture/matrix docs to close `SC-001` and `SC-015`
   truthfully for the repo-owned add/remove seam.
7. Run the direct suites and required named gates.
8. Record the finished session/doc verdict back into the breakdown once code,
   tests, and docs agree.

## Risks and edge cases

- Trust source:
  the authorization check must not trust the inbound `groupConfig` snapshot,
  because that is exactly what a forged event could fake.
- Unsupported role flows:
  do not widen into promotion/demotion support just because the matrix wording
  mentions role events broadly.
- Replay:
  replayed events go through the same listener path and must not bypass the new
  guard.
- Existing protections:
  stale-event and duplicate-event tests must remain green after the auth guard
  lands.

## Exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

## Known-failure interpretation

- Treat failures in the new listener/integration auth regressions as session
  blockers.
- Treat unrelated dirty-worktree failures as blockers only if they intersect
  the listener-auth seam touched here.
- If a named gate fails in an unrelated pre-existing area, record the failing
  command and seam truthfully instead of claiming the gate passed.

## Done criteria

- unauthorized inbound membership events are ignored on both live and replay
  listener paths
- valid authorized membership events still apply
- direct listener and integration regressions pass
- `groups` and `baseline` are rerun and pass or are recorded truthfully as
  unrelated blockers
- the architecture note, matrices, and breakdown all tell the same final story

## Scope guard

- Do not invent signed-event payloads or validator redesign unless the direct
  listener proof shows the repo-owned layer cannot be closed honestly without
  them.
- Do not add unsupported promotion/demotion product flows.
- Do not widen into transport/lifecycle work unless a regression proves replay
  cannot be covered through the current listener seam.
