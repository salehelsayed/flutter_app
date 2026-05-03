# MS-018 Session Plan - Messages created during key rotation bind to exactly one valid epoch

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:50:00+02:00 | Local planner completed | Source matrix MS-018 row; `test-inventory.md`; breakdown MS-018 ordered entry; `send_group_message_use_case.dart`; `group_offline_replay_envelope.dart`; `group_message_listener.dart`; `send_group_message_use_case_test.dart`; `group_key_update_listener_test.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_messaging_smoke_test.dart`; `fake_group_pubsub_network.dart`; `group_test_user.dart` | Existing app-layer tests already cover send-time epoch snapshots, before/during/after local commit sends, pending key-update sends, mixed-epoch inbox replay, and future-epoch placeholder handling. The remaining gap is combined 3-party fake-network proof where A rotates, B sends around B's commit boundary, C receives live deliveries out of order, and all peers persist each message under exactly one epoch. | Add a test-only delivery-hold hook to the fake group network and a row-named 3-party integration test; run focused MS018 and broad groups gates before closure docs. |

## real scope

Close MS-018 with repo-hosted evidence for the shipped epoch model: group sends snapshot the sender's currently committed local key epoch, live transport envelopes carry that exact epoch, and recipients persist the received epoch unchanged even when delivery order differs from send order.

## closure bar

MS-018 can close only when:

- a 3-party fake-network test models A rotating from epoch 1 to epoch 2 while B sends before, during, and after B's local epoch-2 commit boundary
- B's local outgoing rows bind to epochs 1, 1, and 2
- A receives the live transport envelopes and persists the same epochs
- C receives the same live envelopes out of order and still persists each message under exactly one original epoch
- existing send-time snapshot, pending key update, mixed inbox replay, and future-epoch placeholder tests remain green
- source matrix, inventory, and breakdown record `Covered` with concrete file and command evidence

## session classification

`evidence-gated`, resolved by adding row-specific repo evidence. No production behavior change is planned unless the proof exposes a real epoch-binding bug.

## Device/Relay Proof Profile

- Profile for this session: host-only closure with fake-network 3-party proof plus existing app-layer focused tests.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`.
- The row does not claim packet-capture/device-lab proof, account/device registry, MLS-style commit semantics, or transport encryption beyond the shipped live envelope and offline replay contracts.

## files to touch

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- closure docs after evidence passes

## step-by-step implementation plan

1. Add a test-only fake-network hook that can hold live deliveries for one peer/device and later release them in a chosen order.
2. Add a row-named MS018 integration test with Alice rotating, Bob sending before/during/after Bob's local epoch commit, and Charlie receiving held deliveries in reverse order.
3. Assert Bob, Alice, and Charlie persist the same message IDs under epochs 1, 1, and 2, with no duplicate or rewritten epoch.
4. Run focused MS018 commands, then group-message wildcard, groups gate, full groups integration, and `git diff --check`.
5. Update closure docs only after all MS-018 evidence passes.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS018'`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'MS-018'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'send during pending key update uses old epoch until local update commits'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'epoch'`
- `flutter test --no-pub test/features/groups/application/*group_message*_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Source matrix MS-018 row is `Covered`.
- `test-inventory.md` MS-018 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record MS-018 as accepted/Covered.

## scope guard

Do not add vector clocks, MLS commit tracking, account/device registry, packet-capture harnesses, or new transport cryptography under MS-018. This row closes only the shipped `keyGeneration` / `keyEpoch` binding behavior for group messages and offline replay.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:54:30+02:00 | Local executor completed | `fake_group_pubsub_network.dart`; `group_messaging_smoke_test.dart` | Added test-only held message delivery support to the fake group PubSub network and a row-named 3-party MS018 proof where Alice rotates, Bob sends before/during/after Bob's local commit boundary, and Charlie receives live deliveries in reverse order. | Run focused MS018 checks and broad gates before closure docs. |
| 2026-05-01T07:54:30+02:00 | Local verifier completed | Focused MS018 fake-network, send, pending key-update, and inbox replay tests; group-message wildcard; groups gate; full groups integration; `git diff --check` | Accepted: new fake-network proof (`+1`), send MS-018 suite (`+2`), pending key-update send proof (`+1`), epoch inbox replay proof (`+3`), group-message application wildcard (`+213`), `./scripts/run_test_gates.sh groups` (`+101`), full groups integration (`+123`), and `git diff --check` passed. Supporting `group-real-network-nightly` was not run because relay/device env is unset. | Update source matrix, inventory, breakdown counts/ledger/current-session state, and plan final verdict as MS-018 `Covered`. |

## Final Execution Verdict

Accepted. MS-018 is covered for the shipped group-message epoch model: sends snapshot one committed local epoch, live envelopes and offline replay preserve that epoch, and out-of-order 3-party fake-network delivery does not rewrite or duplicate message epochs. The closure is host-only; packet-capture/device-lab proof, account/device registry, MLS commit semantics, and new transport cryptography are not claimed.
