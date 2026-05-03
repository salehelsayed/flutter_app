# MS-003 Session Plan - Clock skew does not corrupt message order

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:18:00+02:00 | Local planner completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; source matrix MS-003 row; `test-inventory.md`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/core/database/helpers/group_messages_db_helpers.dart`; `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`; existing handle-incoming, drain-inbox, fake-network, feed, and wired tests | Existing incoming handling clamps far-future timestamps and DB/fake repositories sort timestamp ties by id, but live UI upserts and group feed projection still contain timestamp-only sort points. MS-003 needs deterministic timestamp/id ordering through live UI and feed projection plus direct live and offline inbox skew tests before the source row can move to `Covered`. | Patch timestamp tie-breakers, add focused MS003 tests, run targeted and groups gates, then close docs only if evidence passes. |

## real scope

Close MS-003 for shipped group-message ordering under clock skew: past, current, near-future, and far-future incoming timestamps must not corrupt stored order, latest-message summaries, live UI order, offline inbox replay order, or group feed projection.

## closure bar

MS-003 can close only when:

- far-future incoming timestamps are clamped before persistence and cannot become the latest row
- past/current/near-future timestamps retain useful chronological display ordering
- equal timestamp ties are deterministic by message id in live UI upserts and group feed projection
- fake-network live and offline inbox replay tests prove skewed messages do not corrupt order or latest selection
- focused MS003 tests, relevant full files, groups gate, full groups integration, and `git diff --check` pass
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`implementation-ready`, because the source row is `Open` and current repo evidence shows direct timestamp-only tie gaps in user-visible live/feed paths.

## Device/Relay Proof Profile

- Profile for this session: `host-only` closure with supporting real-network/nightly evidence unconfigured.
- MS-003 can close on repo-local app/fake-network/offline-inbox proof because the behavior is timestamp normalization and deterministic local ordering.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`.

## files to touch

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
- closure docs after evidence passes

## step-by-step implementation plan

1. Add deterministic timestamp-then-id comparators to live group conversation upserts and group feed projection.
2. Add focused MS003 tests for direct handler skew normalization/order, offline inbox far-future clamp/latest selection, fake-network live skew convergence, wired live equal-timestamp order, and feed projection equal-timestamp latest selection.
3. Run focused MS003 commands first, then full touched test files as needed, the canonical groups gate, full groups integration, and `git diff --check`.
4. Update closure docs only after all MS-003 evidence passes.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'MS003'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'MS003'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS003'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'MS003'`
- `flutter test --no-pub test/features/feed/domain/utils/group_group_messages_into_threads_test.dart --plain-name 'MS003'`
- `flutter test --no-pub test/features/groups/application/*group_message*_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Source matrix MS-003 row is `Covered`.
- `test-inventory.md` MS-003 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record MS-003 as accepted/Covered.

## scope guard

Do not add vector clocks, causal DAGs, previous-state references, clock-sync infrastructure, or real-device transport harness under MS-003. Causal references and concurrent-send ordering beyond timestamp/id order stay MS-004-owned.

## Dirty Worktree Snapshot

Captured at `2026-05-01T07:18:00+02:00`: the tree already contains prior rollout changes in docs, Go node tests, Flutter group code/tests, and untracked prior session plan files. MS-003 execution is scoped to the files listed above unless focused tests expose another row-owned clock-skew ordering gap.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:28:30+02:00 | Local executor completed | `lib/features/groups/presentation/screens/group_conversation_wired.dart`; `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`; focused MS003 tests in handle-incoming, drain-inbox, fake-network smoke, wired, and feed files | Implemented timestamp/id ordering for live conversation upserts and group feed projection, reused existing far-future timestamp clamp, and added direct MS003 coverage for direct handler, offline inbox, live fake-network, wired UI, and feed projection paths. Focused MS003 tests, group-message wildcard, groups gate, full groups integration, and `git diff --check` passed. | Update source matrix, inventory, and breakdown with MS-003 `Covered` evidence. |
| 2026-05-01T07:32:30+02:00 | Local closure reviewer completed | Source matrix MS-003 row; `test-inventory.md` MS-003 crosswalk; breakdown counts, row inventory, session ledger, ordered session row, current closure state, closure progress, and stale-status grep | MS-003 is accepted for shipped timestamp normalization plus deterministic timestamp/id ordering in live UI and feed projection. Supporting `group-real-network-nightly` remains unrun because relay/device env is unset. MS-004 retains causal-reference and concurrent-ordering scope beyond timestamp/id ties. | Continue to the next unresolved source row. |

## Final Execution Verdict

Accepted. MS-003 is covered for the shipped behavior: far-future incoming message timestamps are clamped before persistence and latest selection, past/current/near-future timestamps retain useful chronological order, and equal timestamp ties are deterministic by message id in live conversation upserts and group feed projection. Focused MS003 tests passed for direct handler (`+2`), offline inbox (`+1`), fake-network live skew (`+1`), wired UI (`+1`), and feed projection (`+1`); broader regression gates passed for the group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check`. `group-real-network-nightly` was not run because relay/device env is unset. MS-004 remains responsible for causal references and concurrent ordering beyond timestamp/id ordering.
