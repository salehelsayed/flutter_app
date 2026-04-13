# Session Plan: MD-005

## Row Contract

- source row: `MD-005`
- matrix contract: Message-level behavior stays consistent when entering the same group from `Orbit`, `Feed`, or push.
- current source truth before execution: `Partial`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof shows:
  - `Orbit` entry lands on the shared group conversation surface with the same long-press and reaction behavior
  - `Feed` entry lands on that same message-level contract
  - push / notification-anchor entry preserves targeted-message context and the same reaction-inspection behavior on the shared surface

## Scope Guard

- keep scope on entry-point parity only
- reuse the existing Orbit, Feed, and push-routing coverage instead of broadening into unrelated navigation or notification delivery gaps
- prefer one narrow widget regression over product-code changes unless the shared surface actually diverges

## Planned Proof

1. Reconcile the existing Orbit and Feed parity tests with the row contract.
2. Add one notification-anchor widget regression proving push entry keeps reaction inspection aligned with the shared conversation surface.
3. Run the targeted push-entry parity proof and then update the matrix, inventory, and breakdown.

## Files Expected

- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
