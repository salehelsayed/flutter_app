# DB-004 Session Plan - Transactional update boundaries survive crash

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:08:00+02:00 | Local planner completed | DB-004 source matrix row; `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; `test-inventory.md`; `lib/core/database/helpers/group_messages_db_helpers.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `test/core/database/helpers/group_messages_db_helpers_test.dart`; `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`; `test/core/database/helpers/group_event_log_db_helpers_test.dart`; focused cursor tests | DB-004 cannot close as `Covered` because the repo still has no durable group sync/inbox cursor table/helper, no first-class group receipt table/helper, and no production transaction owner spanning message insert, receipt/read-state update, and cursor advancement. Adjacent message helper and transient cursor evidence exists only. | Rerun focused adjacent evidence, persist DB-004 as `Partial`/prerequisite-blocked, and keep the overall program `still_open`. |

## real scope

DB-004 asks for crash-safe transactional grouping across group message insert, receipt/read-state update, and sync cursor advancement. The current shipped repo can prove durable group message helper behavior and transient relay cursor continuation, but not the full DB-004 closure bar because the cursor and receipt primitives that need to share a transaction do not exist as durable group database owners.

## closure bar

DB-004 can move to `Covered` only when:

- group inbox/sync cursor state is durable in local storage with a named helper or repository owner
- group read/delivery receipt state is first-class enough to participate in the same apply boundary as a message insert
- production replay/apply code updates message row, receipt/read-state, and cursor in one transaction or otherwise proves atomic crash recovery for that tuple
- focused crash-window or transaction-failure tests prove no half-applied state creates duplicate messages, lost receipts, or an advanced cursor without rows

## session classification

`prerequisite-blocked`. The row was initially listed as `needs_tests_only`, but direct audit shows there are missing product/database primitives, not just missing assertions around existing code.

## Device/Relay Proof Profile

- Profile for this session: host-only database/application audit.
- Live device/relay evidence is not the blocker; the blocker is missing durable local cursor/receipt state and a transaction owner.

## files touched

- closure docs only

## evidence checked

- `rg -n 'group_sync|sync_cursor|inbox_cursor|group_inbox_cursor|group_receipt|delivery_receipt|read_receipt|receipt' lib/core/database/migrations lib/core/database/helpers lib/features/groups/domain lib/features/groups/application` returned no matching durable group cursor or receipt table/helper owner.
- `drain_group_offline_inbox_use_case.dart` uses a local in-memory `cursor` variable while draining pages, not a durable DB cursor.
- `group_messages_db_helpers.dart` has message rows and `read_at` helpers, but no transaction owner that combines message insert, receipt/read-state, and cursor advancement.
- `group_event_log_db_helpers.dart` has transactional event-log append and hash-chain verification; that is useful adjacent evidence, but it is not the DB-004 message/receipt/cursor transaction tuple.

## exact tests and gates run

- `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart` passed (`+65`) after rerun without overlapping Flutter commands.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'cursor'` passed (`+4`).
- `git diff --check` must pass after closure docs.

## blocker class

- `missing_durable_group_sync_cursor_owner`
- `missing_group_receipt_owner`
- `missing_transactional_apply_boundary_for_message_receipt_cursor`

## done criteria for this blocked session

- Source matrix DB-004 remains `Partial` with the missing primitives named directly.
- `test-inventory.md` DB-004 crosswalk records the 2026-05-01 evidence rerun and blockers.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and classification counts record DB-004 as `prerequisite-blocked`.
- No `Covered` or accepted DB-004 claim is made.

## scope guard

Do not invent a cursor or receipt model inside documentation. Future closure needs real production schema/helper ownership and crash-window tests before DB-004 can become `Covered`.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:10:00+02:00 | Local evidence auditor completed | DB-004 source row; `test-inventory.md` DB-004 note; code search for durable group cursor/receipt owners; `drain_group_offline_inbox_use_case.dart`; group message/event-log helper tests | Blocked. Adjacent DB helper and transient cursor tests pass, but the durable group sync cursor, first-class group receipt owner, and shared transactional apply boundary are absent. | Persist DB-004 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. DB-004 remains `Partial` because the repo lacks the durable cursor and receipt primitives needed to prove the row's atomic message/receipt/cursor crash boundary. Adjacent message helper, event-log, and cursor continuation evidence is green, but it cannot satisfy DB-004 without a real production transaction owner for the full tuple.
