# Session Plan: RY-010

## Row Contract

- source row: `RY-010`
- matrix contract: Replay without `GroupMessageListener` or without `reactionRepo` never silently claims full convergence.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof shows:
  - every supported replay entry point in the shipped app passes the full replay dependencies, or the missing-dependency path is made explicit
  - invite acceptance no longer drains backlog in a degraded no-`reactionRepo` state
  - the repaired invite-accept path immediately replays both backlog messages and reactions in the same accept flow

## Scope Guard

- keep scope on replay dependency truth only
- do not broaden into later bridge-error recovery or entry-point parity work beyond the minimal invite-accept wiring needed to close this row
- prefer a small wiring fix plus direct regressions over inventing a new surfaced UX contract

## Planned Proof

1. Wire `acceptPendingGroupInvite(...)` to forward `reactionRepo` into `drainGroupOfflineInboxForGroup(...)`.
2. Pass the existing reaction repository from the shipped invite-accept UI entry points.
3. Add a direct use-case regression and a widget-level accept-path regression proving invite acceptance replays both the backlog message and its reaction in one catch-up window.
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
