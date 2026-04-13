# Session Plan: RY-011

## Row Contract

- source row: `RY-011`
- matrix contract: Invite-accept drain includes offline reactions in the same user-visible catch-up window, or the deferred model is explicitly owned.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof shows:
  - invite acceptance drains backlog reactions in the same immediate catch-up flow as backlog messages
  - the shipped accept surface does not clear the pending row before the recovered message and reaction are already durable locally
  - no later global recovery is required to make the first truthful post-accept conversation state visible

## Scope Guard

- keep scope on the invite-accept catch-up window only
- reuse the RY-010 wiring fix where it is already the narrow owner of this gap
- do not broaden into later bridge-error convergence or unrelated replay ordering rows

## Planned Proof

1. Reuse the repaired `acceptPendingGroupInvite(...)` reaction replay wiring.
2. Keep the direct unit regression proving accept drains backlog reactions when `reactionRepo` is supplied.
3. Keep the widget-level shipped-path regression proving the group-list accept flow persists the replayed message and reaction before the pending row disappears.
4. Run the targeted tests.

## Files Expected

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
