# 70 - Group Reaction Replay Store Durability

## 1. Title and Type

- Title: `Group Reaction Replay Store Durability`
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/70-group-reaction-replay-store-durability.md`

## 2. Problem Statement

- Users expect group reactions to converge for offline members the same way
  group messages already do.
- Today, a sender can add or remove a group reaction, see that change succeed
  locally, and still fail to queue the replay copy needed for offline members.
- When that sender-side replay-store step fails, the current product keeps the
  live/local success but does not own a later recovery path for the missed
  reaction replay.
- From the user perspective, that means an offline member can reconnect later
  and still miss a reaction add or remove that other members already saw.

## 3. Impact Analysis

- Affects discussion and announcement groups whenever at least one member is
  offline during a reaction add or remove.
- Affects senders who believe the reaction is fully shared after a successful
  live/local action.
- Affects offline recipients who later reconnect and may see stale reaction
  truth compared with online peers.
- Repo evidence does not show this as a release-blocking contradiction today,
  but it is still a real reliability gap in the shipped group reaction flow.
- The gap is most visible during transient relay or bridge failures where
  `group:inboxStore` fails even though live publish succeeded.

## 4. Current State

Affected code areas and evidence:

- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/remove_group_reaction_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Current user-visible flow as the repo owns it today:

- `sendGroupReaction(...)` publishes the reaction live, triggers a best-effort
  replay-store helper, persists the reaction locally, and returns success.
- If that replay-store helper throws, the flow emits
  `GROUP_REACTION_INBOX_STORE_FAILED` and still returns success to the caller.
- `removeGroupReaction(...)` has the same best-effort replay-store behavior for
  reaction removal, but its failure path is fully swallowed after live publish.
- `retryFailedGroupInboxStores(...)` only retries outgoing group message rows
  with persisted `inboxRetryPayload`; it does not cover reaction add/remove
  replay-store failures.
- Resume and pending-message retry wiring in `handle_app_resumed.dart`,
  `pending_message_retrier.dart`, and `main.dart` therefore retry message inbox
  stores, not reaction replay stores.
- Existing tests already prove live reaction happy paths and replay happy paths
  when replay storage succeeds, especially in
  `group_resume_recovery_test.dart`.
- No direct repo-local test currently proves one owned recovery path for
  sender-side reaction replay-store failure on add or remove.

Important constraints and edge conditions already present:

- Current receive-side reaction truth is stronger than before: mismatched outer
  sender versus inner payload sender is now rejected on live and replay
  receive.
- The residual gap is narrower than general reaction correctness. It is
  specifically about sender-side durability when replay storage fails after
  live publish.
- Group message inbox retry already exists and is deliberately row-backed.
  Reaction replay durability currently does not have an equivalent owned queue
  or retry owner.

## 5. Scope Clarification

In scope:

- user-visible durability of group reaction add/remove for offline recipients
  when sender-side replay storage initially fails
- discussion and announcement reaction flows
- eventual convergence expectations across live peers and later reconnecting
  peers
- preserving truthful reaction state after retry or later recovery

Explicit non-goals:

- redesigning group reaction UI, reaction inspection, or long-press behavior
- reopening receive-side sender-binding work
- changing general group message replay durability, retention, or encryption
  scope
- introducing new announcement product behavior outside the existing reaction
  contract
- redesigning contact eligibility, onboarding, or member-role policy

Accepted ambiguities for a later implementation pass:

- whether the durable owner is a persisted retry queue, an existing recovery
  owner extension, or another bounded sender-owned mechanism
- whether the sender gets any new visible warning or whether the fix stays
  fully silent as long as eventual peer convergence is truthful
- whether add and remove share one persistence owner or parallel owners, as
  long as both user-visible contracts are covered

## 6. Test Cases

### Happy Path

- A reacts to a group message while B is online and C is offline. Even if the
  first sender-side replay-store attempt fails, C later reconnects and sees the
  same reaction add that A and B already see.
- A removes a previously visible group reaction while C is offline. Even if the
  first sender-side replay-store attempt fails, C later reconnects and sees the
  reaction removal instead of stale retained reaction state.
- In an announcement group, a non-admin reader can still add or remove a
  reaction under the same durable offline-replay contract.
- A later reconnecting member sees the final reaction truth exactly once after
  retry or recovery. The product does not show duplicate reactors or duplicate
  remove effects because the replay-store owner retried.

Existing direct coverage today:

- `test/features/groups/application/send_group_reaction_use_case_test.dart`
  covers live reaction send success and publish failure.
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
  covers live reaction removal success and membership guards.
- `test/features/groups/integration/group_resume_recovery_test.dart` covers
  replay happy paths when replay storage already succeeded.

Current gap:

- no direct test proves offline recipient convergence after sender-side
  reaction replay-store failure on add or remove.

### Edge Cases

- A transient `group:inboxStore` failure during reaction add does not strand the
  replay permanently. Later shipped recovery still delivers the missing
  reaction to offline members.
- A transient `group:inboxStore` failure during reaction remove does not strand
  stale reaction state for offline members after they reconnect.
- Recovery of the missed replay does not create duplicate add/remove effects if
  a live peer already processed the same reaction earlier.
- Resume, retry, or later recovery can run more than once without causing the
  same offline member to receive multiple copies of the same reaction change.
- If an offline member reconnects after both an add and a later remove for the
  same message, the recipient converges to the final reaction truth instead of
  replaying an out-of-date intermediate state forever.

Current partial evidence:

- `group_resume_recovery_test.dart` already proves replayed reaction recovery
  and dedupe when replay storage exists.
- `retry_failed_group_inbox_stores_use_case.dart` and its tests prove that
  group-message inbox retry has an owned lane today, which highlights the lack
  of an equivalent reaction-replay owner.

Gap:

- no current direct test covers sender-side reaction replay-store failure with
  later convergence ownership.

### Preservation / Regression

- Existing live reaction behavior remains intact: online peers still see
  immediate reaction updates when publish succeeds.
- Existing reaction add/remove permission rules stay intact for discussion and
  announcement groups.
- Existing replay happy paths in `group_resume_recovery_test.dart` stay green;
  the durability improvement must not break already-working replay storage.
- Existing receive-side sender-binding truth stays intact; the durability fix
  must not reopen the now-closed sender-mismatch seam.
- Existing group message inbox retry ownership remains truthful and does not
  regress while reaction durability is improved.

Explicit preservation regression case:

- If sender-side replay storage fails for a group reaction and the app later
  resumes or retries recovery, offline recipients still converge to the final
  reaction truth without duplicate reaction rows, duplicate removals, or
  silent permanent loss of that reaction change.
