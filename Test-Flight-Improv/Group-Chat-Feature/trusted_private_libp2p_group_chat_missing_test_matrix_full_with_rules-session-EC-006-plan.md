# EC-006 Session Plan - Replayed tombstones cannot corrupt current state

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:54:00+02:00 | Local planner completed | EC-006 source matrix row; ordered-session EC-006 row; `group_message_listener_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_membership_smoke_test.dart`; `invite_round_trip_test.dart`; scoped search for ban, unban, remote delete, and tombstone event families | Existing evidence covers shipped replay behavior for removal, voluntary-leave-as-removal, dissolve, local delete, and re-invite after removal. The row still names tombstone families that are not first-class shipped event models, especially ban, unban, and remote delete. | Rerun focused positive evidence, then persist EC-006 as `Partial`/prerequisite-blocked without changing production code. |

## real scope

EC-006 asks for tombstone replay across old delete, leave, remove, ban, unban, and dissolve tombstones, including replay before and after rejoin or re-invite. Current shipped coverage includes removal/self-removal, voluntary leave represented as `member_removed`, dissolve replay, local deleted-group guards, and remove/rotate/re-invite convergence. It does not cover every tombstone family named by the row because ban, unban, and remote delete tombstones are not first-class production group event models.

## closure bar

EC-006 can move to `Covered` only when:

- replayed tombstones are idempotent for every row-named tombstone family
- old tombstones replayed after a valid rejoin/re-invite cannot delete the current membership, keys, or messages outside their scope
- first-class ban, unban, and remote delete tombstone models either exist with direct replay tests or receive an explicit source-matrix product-scope decision
- host/fake-network replay tests and any required real-device proof pass for the completed event-family matrix

## session classification

`prerequisite-blocked`. This is not just missing assertions around existing code: several row-named tombstone families lack production event models.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter application and fake-network evidence.
- Real-network proof is supplemental; the blocker is missing product/event-family primitives.

## files touched

- closure docs only

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'LP003 member_removed self-removal is the ban-equivalent leave path|replayed group_dissolved is idempotent|old system events for a locally deleted group do not recreate group row or visible message'` passed (`+3`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'replayed member_removed routes through listener cleanup instead of saving a chat row|replayed self-removal cuts off later queued inbox traffic for that group|replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'` passed (`+3`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'writer leave emits a durable left-the-group event for remaining members|offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others'` passed (`+2`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --name 'remove -> rotate -> re-invite round-trip gives the rejoined member the rotated epoch|offline removed member reconnects later from inbox-fallback re-invite on the rotated epoch'` passed (`+2`).
- Scoped search for `member_banned`, `member_unbanned`, `group_ban`, `group_unban`, `ban_member`, `unban_member`, `message_deleted`, `remote_message_delete`, `group_message_deleted`, `delete_group_remote`, `group_deleted`, `__sys.*(ban|unban|delete)`, `receipt_ack`, and `group_receipt` in group app/test and Go group paths returned no first-class tombstone model.
- `git diff --check` must pass after closure docs.

## positive evidence

- Self-removal replay routes through listener cleanup, dispatches one group leave, deletes local group state, and does not persist a chat row.
- Self-removal replay cuts off later queued inbox pages for that group.
- Remaining peers accept only removed-sender inbox messages from before `removedAt`.
- Replayed `group_dissolved` is idempotent and dispatches one leave.
- Old system events for a locally deleted group do not recreate group, member, key, or visible message rows.
- Voluntary leave emits a durable left-the-group event for remaining members through the shipped `member_removed` representation.
- Offline dissolve replay converges a peer to dissolved state, blocks later sends, and allows dissolved local cleanup without affecting others.
- Remove/rotate/re-invite flows give a rejoined member the rotated epoch through direct and inbox-fallback invites.

## blocker class

- `missing_first_class_group_ban_tombstone_model`
- `missing_first_class_group_unban_tombstone_model`
- `missing_remote_delete_tombstone_model`
- `missing_all_tombstone_type_replay_matrix`

## done criteria for this blocked session

- Source matrix EC-006 remains `Partial` with positive shipped evidence and blockers named directly.
- `test-inventory.md` gets an EC-006 crosswalk row with the fresh evidence.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and classification counts record EC-006 as `prerequisite-blocked`.
- No `Covered` or accepted EC-006 claim is made.

## scope guard

Do not invent ban, unban, or remote delete tombstone product models inside this closure. Future closure needs product support or an explicit source-matrix scope decision for each named tombstone family.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:55:00+02:00 | Local evidence auditor completed | Focused tombstone replay, offline drain, membership smoke, re-invite integration tests, and scoped event-family search | Blocked. Shipped tombstone replay paths are strong, but not exhaustive for every EC-006 tombstone family. | Persist EC-006 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. EC-006 remains `Partial`: the repo has concrete tombstone replay evidence for shipped removal, voluntary-leave-as-removal, dissolve, local delete, and re-invite flows, but the row cannot close until ban, unban, and remote delete tombstones have first-class models plus replay tests or an explicit source-matrix scope decision.
