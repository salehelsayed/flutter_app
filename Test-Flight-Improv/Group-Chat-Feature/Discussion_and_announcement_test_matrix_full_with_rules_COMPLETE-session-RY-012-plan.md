# Session Plan: RY-012

## Row Contract

- source row: `RY-012`
- matrix contract: Invite acceptance that returns `bridgeError` still converges to a live joined group without needing the invite row again.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof shows:
  - invite acceptance returns `bridgeError` only after persisting the group and clearing the pending invite row
  - the shipped accept surface tells the user recovery is still catching up instead of implying a clean join
  - a later owned recovery path can rejoin and drain backlog successfully without recreating or reusing the pending invite row

## Scope Guard

- keep scope on the accepted-but-degraded bridge-error contract only
- do not broaden into unrelated replay ordering or reaction catch-up work
- prefer proof-only closure unless a real recovery gap appears

## Planned Proof

1. Add a unit regression proving `bridgeError` leaves the group persisted and the pending invite row cleared.
2. Add a widget regression proving the shipped group-list accept surface shows the explicit recovery-catching-up message.
3. Add an integration regression proving a later `rejoinGroupTopics(...)` plus `drainGroupOfflineInboxForGroup(...)` recovery closes the gap without the invite row.
4. Run the targeted tests.

## Files Expected

- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
