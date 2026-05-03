# MS-004 Session Plan - Deterministic ordering and causal references under concurrent sends

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:42:00+02:00 | Local planner completed | Source matrix MS-004 row; `test-inventory.md`; breakdown MS-004 ordered entry; `group_messages_db_helpers.dart`; `group_message_repository_impl.dart`; `in_memory_group_message_repository.dart`; `group_conversation_wired.dart`; `group_group_messages_into_threads.dart`; existing MS004 fake-network and resume replay tests | Existing timestamp/id ordering and quoted-message propagation are partial. The remaining repo-owned gap is that loaded timelines, live UI upserts, and feed projection do not consistently place a quoted parent before its reply when timestamp/id ordering would place the reply first. `quotedMessageId` is the shipped causal parent reference; previous-state DAG/vector-clock semantics remain out of scope for this row. | Add shared causal timeline ordering for loaded group-message lists, strengthen MS004 tests for parent-before-reply under equal or skewed timestamps, run focused and groups gates, then close docs only if source MS-004 can move to `Covered`. |

## real scope

Close MS-004 for the shipped group-message model: concurrent sends must converge to deterministic timestamp/id order, and quoted replies must keep the parent-before-reply causal display order when both rows are locally available through live, repository, feed, and offline replay paths.

## closure bar

MS-004 can close only when:

- loaded group timelines have deterministic timestamp/id ordering for unrelated concurrent messages
- when a message has a `quotedMessageId` whose parent is present in the same loaded timeline, the parent is ordered before the reply even if timestamp/id would otherwise place the reply first
- live conversation upserts and group feed projection use the same causal timeline ordering
- fake-network live and offline replay tests prove A/B/C concurrent messages plus quoted replies converge to the same order and preserve the parent references
- focused MS004 tests, relevant full files, groups gate, full groups integration, and `git diff --check` pass
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`implementation-ready`, overriding the previous evidence-gated posture under implementation-committed gap-closure mode because the remaining gap is implementation-owned and belongs directly to MS-004 owner files.

## Device/Relay Proof Profile

- Profile for this session: host-only closure with fake-network A/B/C plus offline replay evidence.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`.
- The row closes on the shipped `quotedMessageId` causal parent reference. It does not claim vector clocks, previous-state DAGs, cross-device account registries, or packet-capture/device-lab proof.

## files to touch

- `lib/features/groups/domain/utils/group_message_ordering.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- closure docs after evidence passes

## step-by-step implementation plan

1. Add a shared group-message timeline-ordering helper: timestamp/id deterministic order first, then parent-before-reply promotion for present `quotedMessageId` parents with cycle-safe fallback.
2. Use that helper in repository loads, fake repository loads, live conversation upserts, and group feed projection.
3. Add focused MS004 tests for repository causal order, feed order, wired live order, fake-network concurrent A/B/C quoted replies, and offline replay parent/reply order when timestamp/id would otherwise invert them.
4. Run focused MS004 commands first, then owner files, the canonical groups gate, full groups integration, and `git diff --check`.
5. Update closure docs only after all MS-004 evidence passes.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'MS004'`
- `flutter test --no-pub test/features/feed/domain/utils/group_group_messages_into_threads_test.dart --plain-name 'MS004'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'MS004'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS004'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'MS004'`
- `flutter test --no-pub test/features/groups/application/*group_message*_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Source matrix MS-004 row is `Covered`.
- `test-inventory.md` MS-004 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record MS-004 as accepted/Covered.

## scope guard

Do not add vector clocks, previous-state DAGs, CRDT ordering, account/device registry, or real-device transport harness under MS-004. The shipped causal reference for this row is `quotedMessageId`; broader key epoch binding remains MS-018-owned.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:45:30+02:00 | Local executor completed | `group_message_ordering.dart`; `group_message_repository.dart`; `group_message_repository_impl.dart`; `in_memory_group_message_repository.dart`; `group_conversation_wired.dart`; `group_group_messages_into_threads.dart`; MS004 repo/feed/wired/smoke/resume tests | Implemented shared causal timeline ordering for loaded group-message lists: timestamp/id deterministic order for unrelated messages, present quoted parent before reply, and cycle-safe fallback. Repository, fake repository, live wired conversation, and feed projection use the shared helper. | Run focused and broad gates, then close docs only if source MS-004 can move to `Covered`. |
| 2026-05-01T07:45:30+02:00 | Local verifier completed | Focused repo/feed/wired/fake-network/resume MS004 tests; group-message application wildcard; groups gate; full groups integration; `git diff --check` | Accepted: focused repo (`+2`), feed (`+1`), wired (`+1`), fake-network live (`+1`), resume replay (`+1`), group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+100`), full groups integration (`+122`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. | Update source matrix, inventory, breakdown counts/ledger/current-session state, and plan final verdict as MS-004 `Covered`. |

## Final Execution Verdict

Accepted. MS-004 is covered for the shipped group-message model: concurrent unrelated messages converge through deterministic timestamp/id ordering, and loaded/live/feed/offline timelines place a present quoted parent before its reply while preserving `quotedMessageId`. The closure is host-only and fake-network/offline-replay backed; no vector clocks, previous-state DAG, account/device registry, real-device packet proof, or broader MS-018 key-epoch binding is claimed.
