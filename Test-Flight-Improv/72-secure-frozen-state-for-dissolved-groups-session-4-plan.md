# Session 4 Plan - Ship a truthful local-delete-after-dissolve cleanup flow with device-backed proof

## Final verdict

- `implementation-ready`

## Real scope

- Add one shipped dissolved-only cleanup entry point on `GroupInfo`, keeping
  active-group leave behavior unchanged.
- Make the cleanup copy explicit: dissolved history may stay on-device until
  the user chooses to delete it locally, and that cleanup does not affect any
  other member.
- Tighten the local delete helper so dissolved-group cleanup does not publish
  `group:leave`, does not emit new membership-side effects, and still purges
  local messages, members, keys, and the group row.
- Add direct widget/use-case/integration proof plus one widget-driven
  `integration_test/` flow that exercises offline dissolve recovery into a
  visible cleanup action and verifies the delete stays device-local.

## Closure bar

- Dissolved `GroupInfo` shows a user-facing local cleanup action with truthful
  copy and no return of active management controls.
- Active groups still show the existing leave/dissolve behavior and do not
  gain the new local-delete action.
- The dissolved cleanup path removes local group history and repo state
  without publishing `group:leave` or any new dissolve/membership event.
- Confirmation copy makes the action clearly device-local and optional.
- Multi-user regression proof shows an offline member can recover the
  dissolved state, keep preserved history, and later delete that dissolved
  group locally without redefining the dissolve globally.
- A widget-driven `integration_test/` proves the surfaced cleanup action is
  visible after recovery and that confirming it clears only local state.

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
  - `lib/features/groups/application/delete_group_and_messages_use_case.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`

On disagreement:

- current code and tests beat older prose
- `test-gate-definitions.md` is the source of truth for named gates
- the dissolved cleanup path must be more truthful than the older Orbit
  delete flow, because Session `4` explicitly requires device-local cleanup
  rather than a generic leave-and-delete action

## Session classification

- `implementation-ready`

## Exact problem statement

- `GroupInfoScreen` currently tells users a dissolved group is read-only and
  hides `Leave Group`, but it gives them no explicit way to remove that
  history later.
- The existing `deleteGroupAndMessages(...)` helper is not yet safe for the
  dissolved cleanup contract because it always calls `leaveGroup(...)`, which
  publishes `group:leave` and performs active-group leave semantics.
- Orbit already exposes a destructive delete action, but its copy and helper
  semantics describe "leave + delete" rather than the report's required
  dissolved-only local cleanup contract.
- This session must make the local cleanup truth visible to users while
  keeping dissolve finality intact for everyone else.

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/delete_group_and_messages_use_case.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Tests:
  - `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`

## Existing tests covering this area

- `delete_group_and_messages_use_case_test.dart`
  proves message purge order and error propagation, but today it asserts the
  helper publishes `group:leave`, which is exactly the dissolved-local-delete
  gap this session must tighten.
- `group_info_screen_test.dart`
  already proves dissolved groups show status and hide management controls,
  but it does not yet expose a truthful local cleanup affordance.
- `group_info_wired_test.dart`
  already proves leave and dissolve flows pop/navigate correctly, making it
  the right seam to verify the new confirmation and local-only deletion path.
- `group_membership_smoke_test.dart`
  already proves offline replay can converge a member into the dissolved state
  and block later sends, but it does not yet prove optional local cleanup.
- `group_recovery_e2e_test.dart`
  already exercises simulator-backed recovery seams with `IntegrationTest`,
  but it does not yet pump a surfaced dissolved cleanup action.

## Regression/tests to add first

- Add a use-case regression that dissolved local delete purges local data
  without publishing `group:leave`.
- Keep the active non-dissolved delete path covered so Orbit-style
  leave-and-delete semantics do not silently regress.
- Add `GroupInfoScreen` regressions for:
  - dissolved groups show the local delete action and local-only explanatory
    copy
  - active groups keep `Leave Group` and do not show the local delete action
- Add `GroupInfoWired` regressions for:
  - tapping the dissolved cleanup action opens a confirmation dialog
  - confirm deletes local state, does not publish `group:leave`, and pops back
    out of the group flow
  - cancel leaves the route and local state untouched
- Extend `group_membership_smoke_test.dart` so an offline recovered dissolved
  member can still delete the group locally without affecting anyone else.
- Add a widget-driven `integration_test/group_recovery_e2e_test.dart`
  regression that pumps the recovered dissolved `GroupInfoWired` surface,
  shows the cleanup affordance, confirms it, and verifies only local state was
  removed.

## Step-by-step implementation plan

1. Add the direct regressions listed above so the dissolved local-delete seam
   is red first.
2. Tighten `deleteGroupAndMessages(...)` with an explicit dissolved/local-only
   mode, or replace it with a narrower helper, so dissolved cleanup purges
   local state without calling `leaveGroup(...)`.
3. Keep active delete semantics unchanged for existing non-dissolved callers.
4. Extend `GroupInfoScreen` with a dissolved-only cleanup card/button and
   truthful local-only copy.
5. Wire the new action in `GroupInfoWired` with confirmation, success
   navigation, and failure snackbar behavior.
6. Add the offline-recovery integration proof in both the feature integration
   suite and the widget-driven `integration_test/` seam.
7. Run the direct suites, the targeted recovery suite, the `groups` gate, and
   the device-backed `integration_test` flow.

## Risks and edge cases

- Reusing `leaveGroup(...)` for dissolved cleanup would violate the
  user-facing contract by publishing a new leave event after the group is
  already over.
- Tightening `deleteGroupAndMessages(...)` must not break existing active
  Orbit delete behavior if that flow still expects leave-and-delete semantics.
- The `GroupInfo` affordance must stay clearly optional; dissolved users may
  keep history without being forced into immediate cleanup.
- Success navigation should leave the user out of the deleted conversation
  flow and not strand them on a now-invalid `GroupInfo` route.

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
- Targeted integration test:
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
- Device-backed widget integration:
  - `flutter test integration_test/group_recovery_e2e_test.dart -d <device>`
- Named gates:
  - `./scripts/run_test_gates.sh groups`

## Known-failure interpretation

- The worktree is already dirty in unrelated notification/push files. Treat
  failures outside the touched dissolved-cleanup seam as pre-existing unless
  the direct cleanup suites, targeted recovery suite, or `groups` gate show a
  regression in touched files.
- If the device-backed `integration_test` cannot run because no device is
  available in the environment, record that honestly after all host-side proof
  passes.

## Done criteria

- Dissolved users can explicitly delete the group locally from a shipped
  cleanup surface.
- The cleanup copy says the action is local-only and optional.
- Confirmed cleanup removes the local group row, members, keys, and messages.
- Dissolved cleanup does not publish `group:leave`.
- Active leave behavior remains unchanged.
- Offline-recovered dissolved state can still be cleaned up locally.
- The direct suites and `groups` gate pass, or any unrelated pre-existing
  failure is documented honestly.

## Scope guard

- Do not redesign active-group delete/leave UX beyond preserving current
  behavior.
- Do not widen this session into feed/thread projection; Session `3` already
  owns that work.
- Do not refresh stable docs or gate-definition prose here; Session `5` owns
  closure docs.
- Do not reopen dissolve authority or reaction-freeze logic unless a new red
  test proves this session cannot verify without a narrow follow-up.

## Accepted differences / intentionally out of scope

- Orbit's existing generic delete action can remain unchanged in this session
  as long as the dissolved-group-facing shipped path becomes truthful.
- Exact visual styling of the cleanup affordance may differ from existing
  destructive buttons as long as the local-only semantics are explicit.
