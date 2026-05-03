# ER-002 Session Plan - Unknown and removed sender quarantine has no ghost UI rows

Status: covered

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:32:00+02:00 | Local planner completed | ER-002 source matrix row; ordered-session ER-002 row; `handle_incoming_group_message_use_case.dart`; `handle_incoming_group_reaction_use_case.dart`; focused message/reaction/listener/member-smoke tests | The current app path still allowed unknown message and reaction senders as stale-member tolerance, which creates visible ghost state. This is row-owned and can be fixed by failing closed for unknown senders while preserving pre-removal cutoff tolerance. | Patch message/reaction unknown-sender handling and add focused no-storage/no-stream/no-notification tests. |

## real scope

ER-002 covers shipped app-layer handling for valid-looking group messages and reactions from unknown senders and removed senders. The row requires no visible ghost rows and no local notifications for rejected traffic.

## closure bar

ER-002 can move to `Covered` when:

- unknown message senders without a persisted removal cutoff are rejected before DB storage, stream emission, and local notification
- removed-sender messages at or after the persisted cutoff are rejected, while pre-cutoff messages remain policy-allowed
- unknown reactions are rejected before reaction storage or UI change emission
- removed-member notification suppression remains covered through fake-network integration

## session classification

`implementation-ready`, resolved with row-owned code and focused tests.

## Device/Relay Proof Profile

- Profile for this session: host-only application and fake-network integration proof.
- Real-network proof is supplemental; the row's required 3-party E2E column remains recommended rather than required.

## files touched

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'unknown'` passed (`+3`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name 'unknown sender'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ER002'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member notifications stay off until rejoin becomes effective'` passed (`+1`).
- `git diff --check` must pass after closure docs.

## positive evidence

- `handleIncomingGroupMessage` now rejects unknown senders that have no persisted removal cutoff before event-log append or message persistence.
- The same handler still accepts pre-cutoff removed-sender messages and rejects at-cutoff/later removed-sender replay.
- `handleIncomingGroupReaction` now returns `unknownSender` before reaction storage when the sender is not a current member.
- `GroupMessageListener` has focused proof that an unknown sender message creates no DB row, emits no group message stream item, and shows no local notification.
- The fake-network smoke anchor still proves a removed member receives no notification while removed and resumes notification behavior only after rejoin.

## caveats

- ER-002 covers shipped message and reaction surfaces. First-class receipts are not modeled in this repo and remain outside this row until they exist.
- Pre-removal cutoff tolerance remains intentional: traffic sent before a persisted removal timestamp is not treated as removed-sender ghost traffic.

## done criteria

- Source matrix ER-002 moves from `Partial` to `Covered` with concrete code/test evidence.
- `test-inventory.md` records the ER-002 crosswalk.
- Breakdown current-session state, evidence map, inventory, ledger, ordered row, and source counts record ER-002 as accepted/Covered.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:38:00+02:00 | Local executor completed | Message/reaction handlers and focused tests | Implemented fail-closed unknown-sender message/reaction handling while preserving removed-sender cutoff semantics. Focused tests passed. | Persist ER-002 as `Covered` in source and closure docs. |

## Final Execution Verdict

Covered on 2026-05-01. ER-002 is covered for shipped message, reaction, and notification behavior: unknown senders no longer create ghost rows/reactions/notifications, removed-sender cutoff behavior remains enforced, and removed-member notifications stay suppressed until rejoin.
