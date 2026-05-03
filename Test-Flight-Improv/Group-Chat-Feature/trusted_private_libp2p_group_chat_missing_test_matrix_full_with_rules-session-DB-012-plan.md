# DB-012 Session Plan - Idempotent apply covers every remote event type

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:19:00+02:00 | Local planner completed | DB-012 source matrix row; `test-inventory.md`; `handle_incoming_group_message_use_case_test.dart`; `group_message_listener_test.dart`; `handle_incoming_group_reaction_use_case_test.dart`; `group_key_update_listener_test.dart`; `group_resume_recovery_test.dart`; scoped search for group ban/delete/receipt/commit models | Existing evidence covers many shipped duplicate paths, but the row explicitly lists event families that are not first-class shipped remote apply models: bans, remote message deletes, receipts, and commit/key-package style transitions. DB-012 should stay Partial with explicit blockers. | Rerun focused duplicate/idempotency evidence, then persist DB-012 as `Partial`/prerequisite-blocked. |

## real scope

DB-012 asks for idempotent apply across every remote event type. Current shipped coverage includes duplicate messages, media enrichment, reactions, membership joins/removals, role updates, metadata updates, key-rotation system events, direct key updates, and live-plus-inbox message replay. It does not cover every event family named by the row.

## closure bar

DB-012 can move to `Covered` only when:

- each shipped remote event family has direct duplicate/replay tests proving no duplicate visible timeline spam or state rollback
- explicitly named families that are not currently first-class, including bans, remote message deletes, receipts, and commit/key-package transitions, either get production models plus idempotent apply tests or receive a source-matrix product-scope decision
- offline replay and live replay prove the same idempotency properties for the same event families

## session classification

`prerequisite-blocked`. This is not just missing assertions around existing code: several row-named event families lack first-class production models.

## Device/Relay Proof Profile

- Profile for this session: host-only application/database evidence.
- Real-network proof is supplemental; the blocker is missing product/event-family primitives.

## files touched

- closure docs only

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay'` passed (`+5`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate'` passed (`+9`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name 'duplicate'` passed (`+2`).
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'exact duplicate key update replay keeps one log entry and final key'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'` passed (`+1`).
- `git diff --check` must pass after closure docs.

## positive evidence

- Messages: duplicate replay preserves first trusted fields, ignores tampered timestamp/content, enriches missing quoted/media fields only when safe, and live-plus-inbox replay produces one visible row.
- Media: duplicate replay can fill missing media attachments and rejects oversized enrichment.
- Reactions: duplicate add leaves one stored reaction; duplicate remove leaves reaction absent.
- Membership and roles: duplicate `member_added`, `members_added`, non-self `member_removed`, and `member_role_updated` keep one canonical state/timeline result.
- Metadata: duplicate signed `group_metadata_updated` keeps one metadata timeline row.
- Key events: duplicate `key_rotated` system events stay non-durable; exact duplicate direct `group_key_update` replays keep one event-log entry and final key.

## blocker class

- `missing_first_class_group_ban_event_model`
- `missing_remote_group_message_delete_apply_model`
- `missing_group_receipt_apply_model`
- `missing_commit_or_key_package_apply_model`
- `missing_all_event_family_idempotency_matrix`

## done criteria for this blocked session

- Source matrix DB-012 remains `Partial` with positive evidence and blockers named directly.
- `test-inventory.md` gets a DB-012 crosswalk row with the fresh evidence.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and classification counts record DB-012 as `prerequisite-blocked`.
- No `Covered` or accepted DB-012 claim is made.

## scope guard

Do not invent bans, remote message deletes, receipts, or commit/key-package models under DB-012 documentation. Future closure needs product support or an explicit source-matrix scope decision for each named event family.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:21:00+02:00 | Local evidence auditor completed | Focused duplicate message, system event, reaction, key-update, and live-plus-inbox replay tests; scoped event-family search | Blocked. Shipped duplicate/idempotent paths are strong, but not exhaustive for every DB-012 event family. | Persist DB-012 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. DB-012 remains `Partial`: the repo has concrete idempotency evidence for shipped message, media, reaction, membership, role, metadata, and key-update paths, but the row cannot close until bans, remote message deletes, receipts, and commit/key-package transitions have first-class apply models or an explicit source-matrix scope decision.
