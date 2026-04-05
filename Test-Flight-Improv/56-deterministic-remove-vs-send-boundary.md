# Deterministic Remove-vs-Send Boundary

## 1. Title and Type

- Title: Deterministic remove-vs-send boundary for group membership changes
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`

## 2. Problem Statement

- A group member can be removed while they are composing or while a send is in flight.
- The current repo proves some adjacent behavior, but it does not define one user-visible rule for what should happen at the exact remove-versus-send boundary.
- From a user perspective, that leaves an important correctness question unresolved: whether a message sent around the removal moment is accepted or rejected, and whether every peer converges on that same answer.

## 3. Impact Analysis

- Affects group admins removing members during active conversation and members who are sending at the same time.
- Appears at a high-risk correctness boundary where messaging, membership changes, and replay timing meet.
- Severity is high because this boundary shapes whether post-removal messages are accepted, rejected, duplicated, or shown inconsistently across peers.
- The current rollout is blocked on this unresolved contract for both `MR-015` and `SC-012` in the group gap matrix.

## 4. Current State

- The current architecture note still says ordering remains best-effort in `Test-Flight-Improv/09-network-group-messaging.md`.
- The current in-scope matrix keeps both `MR-015` and `SC-012` open in `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`.
- The repo already proves adjacent behavior:
  - post-removal send rejection after cleanup is part of the current evidence note for `MR-015`
  - send pre-persistence before publish is already covered in `test/features/groups/application/send_group_message_use_case_test.dart`
  - removal and membership convergence coverage exists around `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely code areas shaping the current behavior are:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- The repo evidence is strong enough to say adjacent seams work, but not strong enough to say the exact boundary rule is defined and verified.

## 5. Scope Clarification

- In scope:
  - define one user-visible contract for messages sent at the remove boundary
  - require peer convergence on that contract
  - require direct proof for that boundary in repo-owned tests
- Not in scope:
  - strict total ordering across all concurrent group messages
  - unrelated global transport redesign
  - unsupported admin-role expansion features
- Accepted ambiguity for the later implementation pass:
  - this spec does not choose whether the boundary rule should be sender-first, remover-first, or epoch-based; it only requires that the product define one rule and prove it consistently

## 6. Test Cases

### Happy Path

- When a member is removed before their in-flight message crosses the accepted boundary, the message is rejected and no remaining peer receives it.
- When a member's message crosses the accepted boundary before removal takes effect, peers converge on one accepted delivery outcome and do not later roll it back inconsistently.

### Edge Cases

- If removal and send happen close together while one peer is briefly offline, every peer still converges on the same accepted-or-rejected result after replay and reconnect.
- If the sender retries after removal, the app applies the same defined boundary rule and does not create ghost duplicates or conflicting local state.
- If queued or replayed traffic reaches peers after the removal event, the result still matches the same defined boundary rule rather than depending on arrival timing alone.

### Regressions To Preserve

- Existing post-removal cleanup behavior must keep blocking ordinary sends after the member is already removed.
- Existing pre-persist send durability must keep working for non-removed valid sends.
- Existing removal and rejoin flows outside the exact remove-versus-send race must keep their current behavior.

