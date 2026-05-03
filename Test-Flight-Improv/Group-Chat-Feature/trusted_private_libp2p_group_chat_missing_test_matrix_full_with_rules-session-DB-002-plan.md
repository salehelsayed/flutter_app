# DB-002 Session Plan - Signed append-only or tamper-evident local event log

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:00:00+02:00 | Local planner completed | DB-002 source matrix row; `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; `test-inventory.md`; `lib/core/database/migrations/060_group_event_log.dart`; `lib/core/database/helpers/group_event_log_db_helpers.dart`; `lib/main.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/group_key_update_listener.dart`; focused event-log tests | Existing migration/helper and application tests already prove most event-log behavior, but production `GroupKeyUpdateListener` was not wired to `dbAppendGroupEventLogEntry` from `main.dart`, and DB-002 needed a fresh closure plan after the earlier reset note. | Wire key-update listener event-log append in production, add direct membership/metadata replay test, rerun focused DB-002 evidence, then update closure docs only if the source row can move to `Covered`. |

## real scope

Close DB-002 for the shipped local group event log: accepted incoming group messages, accepted membership/metadata/role system events, `key_rotated` system events, and direct `group_key_update` key commits append to a tamper-evident local hash-chain log; exact replays are idempotent and conflicting replays or row tampering are detected before silent local state mutation.

## closure bar

DB-002 can close only when:

- the `group_event_log` migration provides durable per-group sequence, source-event uniqueness, canonical payload, previous-entry hash, entry hash, and query indexes
- the helper appends in a transaction, canonicalizes payloads deterministically, treats exact duplicates as idempotent, rejects changed replay with `GroupEventLogTamperException`, and verifies chain tampering
- production group message, invite, and direct key-update listener wiring passes `dbAppendGroupEventLogEntry`
- accepted incoming messages, membership/metadata/role system events, `key_rotated` system events, and direct key commits have focused append/replay/tamper tests
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`implementation-ready`, with a narrow production wiring fix because repo-local event-log primitives and most application evidence already existed.

## Device/Relay Proof Profile

- Profile for this session: host-only database/application closure.
- DB-002 does not require live relay/device proof because the row is about local database/event-log mutation and replay behavior.
- `group-real-network-nightly` remains supplemental for other transport rows, not a blocker for DB-002.

## files touched

- `lib/main.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- closure docs after evidence passed

## existing production anchors

- `lib/core/database/migrations/060_group_event_log.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/main.dart`

## step-by-step implementation plan

1. Wire `GroupKeyUpdateListener` in `main.dart` with the same `dbAppendGroupEventLogEntry` callback already used by the group message and invite listeners.
2. Add a focused DB-002 listener test proving accepted `member_added` and signed `group_metadata_updated` events append to the event log and that changed replay of the same source event id is rejected before membership or metadata mutation.
3. Rerun migration/helper event-log tests, incoming-message event-log tests, membership/metadata/role/key-update replay tests, key-rotation duplicate proof, and the fresh full migration-chain schema check.
4. Update DB-002 source matrix, inventory, breakdown counts, current-session state, session ledger, and ordered session row only after the direct evidence passes.

## exact tests and gates run

- `flutter test --no-pub test/core/database/migrations/060_group_event_log_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'event log'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DB002 logs membership and metadata events and blocks changed replay before mutation'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_role_updated logs event and rejects tampered replay before mutation'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate key_rotated system event stays non-durable'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'logs key update and rejects tampered replay before replacing key'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'exact duplicate key update replay keeps one log entry and final key'`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name '1a. Fresh install path creates all tables with correct schema'`
- `git diff --check`

## done criteria

- DB-002 source matrix row is `Covered`.
- `test-inventory.md` DB-002 crosswalk is `Covered`.
- Breakdown counts move to 25 `Covered`, 5 `Open`, and 19 `Partial`.
- Current-session closure state records DB-002 as accepted with blocker class `none`.
- The program verdict remains `still_open` because later rows remain unresolved.

## scope guard

Do not claim MLS signed commit-transition support, first-class key-package replay protection, external device proof, or a per-actor signed audit model under DB-002. The row allows a tamper-evident local event log; those broader cryptographic and replay contracts stay owned by EK-004, EK-012, DB-012, and later security rows.

## Dirty Worktree Snapshot

Captured at `2026-05-01T09:00:00+02:00`: the worktree already contained many prior rollout changes and untracked session plan files. DB-002 execution is scoped to the key-update listener wiring in `lib/main.dart`, one focused listener test, focused DB/application verification, and DB-002 documentation updates.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:03:00+02:00 | Local executor completed | `lib/main.dart`; `test/features/groups/application/group_message_listener_test.dart`; `lib/core/database/migrations/060_group_event_log.dart`; `lib/core/database/helpers/group_event_log_db_helpers.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/group_key_update_listener.dart` | Wired production direct key updates into the DB event-log append helper and added focused membership/metadata replay proof. Existing migration/helper/message/role/key-update anchors cover the rest of the row-owned event families. | Run focused DB-002 gates, then close source docs if all evidence passes. |
| 2026-05-01T09:05:00+02:00 | Local QA accepted | Focused migration/helper tests; incoming message event-log tests; new DB-002 membership/metadata test; role replay test; `key_rotated` duplicate proof; direct key-update tamper and exact replay tests; fresh migration-chain schema check | Accepted. Commands passed: migration/helper event-log suite (`+5`); handle-incoming event-log slice (`+3`); new DB-002 membership/metadata listener test (`+1`); role event-log replay test (`+1`); `key_rotated` duplicate system event proof (`+1`); direct key-update tamper test (`+1`); exact duplicate direct key-update replay test (`+1`); full migration-chain fresh schema check (`+1`). | Update source matrix, inventory, and breakdown to `Covered`/accepted. |

## Final Execution Verdict

Accepted on 2026-05-01. DB-002 is covered for the shipped tamper-evident local event log: database migration/helper code provides a per-group hash chain with replay conflict detection and chain verification, production listeners route accepted group event families into the append helper, and focused tests prove messages, membership, metadata, roles, `key_rotated`, and direct key commits append or replay safely without silent mutation. No MLS signed commit-transition, first-class key-package replay model, or external device proof is claimed by this row.
