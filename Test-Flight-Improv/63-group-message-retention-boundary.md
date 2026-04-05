# 1. Title and Type

- Title: Group Message Retention Boundary
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/63-group-message-retention-boundary.md`
- Matrix row: `UX-008`

# 2. Problem Statement

- Users can already rely on relay-backed offline catch-up for group messages, but the product does not currently define when stored group backlog expires or what a user should see when reconnecting after that boundary.
- Today a user who comes back after a long offline period has no explicit retention promise for missed group messages, no visible expired-versus-retained contract, and no user-facing explanation of what happened if older backlog is unavailable.
- This is a product problem because store-and-forward exists and feels durable, but the repo does not yet tell users how long that durability lasts for group messages.

# 3. Impact Analysis

- Affects users who go offline for extended periods and later rely on group backlog replay to catch up.
- Appears at the boundary between short-lived offline recovery, which is already well covered, and longer offline absence where retention promises matter.
- The current gap is mostly a policy and UX-cost issue rather than an everyday correctness failure: replay works, but users and tests do not have an explicit rule for when backlog should still exist.
- The missing contract also blocks honest closure of the matrix row because the repo cannot verify “expired versus still retained” behavior without a defined boundary.

# 4. Current State

- Group backlog replay is a real product path today. `drainGroupOfflineInbox()` retrieves cursor-paged relay inbox messages and replays them until the cursor is exhausted. Evidence: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- The fake relay used in repo-local tests stores offline inbox messages until retrieval, with no message-retention TTL or expiry rule in that test seam. Evidence: `test/shared/fakes/fake_p2p_network.dart`
- The maintained architecture doc describes relay inbox fallback, cursor-based replay, and recovery, but still treats long-tail retention policy as undefined. Evidence: `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- The repo does have explicit expiry semantics for pending group invites, including a 7-day TTL and visible “Invite expired” UX, which highlights that message-retention expiry is a separate unresolved contract rather than a general lack of expiry handling everywhere. Evidence: `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `test/features/groups/presentation/group_list_screen_test.dart`
- Current direct tests prove replay pagination, replay ordering, removal cutoffs, and recovery after ordinary offline gaps, but they do not prove an expired-message boundary for group backlog. Evidence: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`

# 5. Scope Clarification

- In scope:
  - the user-visible retention boundary for relay-backed group backlog
  - what happens when a user reconnects before that boundary
  - what happens when a user reconnects after that boundary
  - mixed cases where some missed messages are still retained and older ones are not
- Explicit non-goals:
  - redesigning the broader inbox replay mechanism
  - redefining remove-vs-send cutoffs, role validation, or key-rotation rules
  - broad server storage-policy work beyond whatever user-visible contract the product later chooses to expose
- Accepted ambiguities for the later implementation pass:
  - exact retention duration
  - whether expired messages disappear silently, leave a placeholder, or surface explicit copy
  - whether the boundary is global or class-specific, as long as the user-visible rule becomes explicit and testable

# 6. Test Cases

## Happy Path

- A member who reconnects within the supported retention window receives the missed group messages normally and can continue the conversation from the recovered backlog.
- When a reconnecting member has both older and newer missed messages around the retention boundary, the product applies one consistent rule and still recovers the messages that remain inside retention.

## Edge Cases

- A member who reconnects after the retention boundary gets a clear and predictable result for expired backlog instead of ambiguous partial recovery.
- Expired messages do not reappear later on another retry once the product has already treated them as unavailable.
- Retained messages arriving alongside expired ones do not duplicate, reorder incorrectly, or create ghost unread state.
- Recovery after a long offline period still respects existing removal, dissolve, and authorization rules for any messages that remain eligible to replay.

## Regressions To Preserve

- Existing cursor-based group backlog replay continues to work for non-expired messages.
- Existing short-gap startup and resume recovery stays intact for ordinary offline windows.
- Existing remove-vs-send cutoff behavior and replay-safe membership cleanup remain unchanged unless the later product contract explicitly says otherwise.
