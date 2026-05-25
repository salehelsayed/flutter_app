# G3-INV-001 Session Plan And Closure

Source row: G3-003.

## Scope

- Preserve default parse-only invite inspection behavior.
- Add opt-in current-time validation for invite payload parsing.
- Make acceptance reject expired invite policy, invalid/expired welcome package, and stale freshness proof before bridge join work.
- Keep Ed25519 verification bridge-backed; do not add fake Dart crypto to the domain model.

## Closure Evidence

- Implemented in `GroupInvitePayload` and `acceptPendingGroupInvite`.
- Focused tests cover opt-in parse validation and acceptance rejection before bridge work.
- A stale invite replay fixture was corrected to use the accepted recipient identity so backlog reaction replay remains valid under membership gating.
- Verification: included in the controller focused gate, `+169: All tests passed!`.

## Verdict

Accepted and closed.
