# MS-002 Session Plan - Message author, device identity, and Peer ID binding are verified

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:03:40+02:00 | Local planner completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; source matrix MS-002 row; `test-inventory.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/send_group_message_use_case.dart`; `lib/features/groups/domain/models/group_message.dart`; `lib/core/database/helpers/group_messages_db_helpers.dart`; `test/shared/fakes/fake_group_pubsub_network.dart`; `test/shared/fakes/group_test_user.dart`; existing message/inbox tests | Existing Go validation rejects claimed `senderId` versus libp2p transport peer mismatch, but app storage does not persist the verified transport Peer ID and Dart live/inbox paths can accept a supplied payload without a stored transport-binding fact. MS-002 needs a durable `transport_peer_id` field plus focused live, offline-inbox, migration, and helper/model proof. | Add guarded migration 061, persist `transportPeerId`, reject mismatches before message save, update Go received event metadata, add focused tests, run targeted gates, then close docs only if the row can move to `Covered`. |

## real scope

Close MS-002 for the shipped trusted-private identity unit: the libp2p transport Peer ID is the verified sender device identity, and every stored group message records the Peer ID that was observed/validated at the live or offline-replay boundary.

## closure bar

MS-002 can close only when:

- live Go group message received events expose the verified transport Peer ID after validator binding
- Dart live/replay handling rejects messages whose supplied transport Peer ID disagrees with claimed `senderId`
- accepted live and offline-inbox messages persist `transportPeerId` on `GroupMessage`
- migration, model/repository/helper, focused app tests, Go proof, groups gate, full groups integration, and `git diff --check` pass
- source matrix, inventory, and breakdown record `Covered` with concrete file and test evidence

## session classification

`evidence-gated`, with targeted implementation because the current repo evidence is incomplete for durable app-layer sender/transport binding.

## Device/Relay Proof Profile

- Profile for this session: `host-only` closure with supporting real-network/nightly evidence unconfigured.
- MS-002 can close on Go validator/event proof plus repo-local fake/live/inbox proof because the shipped device identity unit is the libp2p Peer ID.
- Supporting unrun gate: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`.

## files to touch

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `lib/core/database/migrations/061_group_message_transport_peer_id.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `test/core/database/migrations/061_group_message_transport_peer_id_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- closure docs after evidence passes

## step-by-step implementation plan

1. Add migration 061 for nullable `group_messages.transport_peer_id`, wire it into `main.dart`, and update model/helper row mapping.
2. Add `transportPeerId` to `GroupMessage`, live listener, inbox drain, and outgoing retry/inbox payloads.
3. Reject live/replay messages when a non-empty transport Peer ID differs from claimed `senderId`, before event-log or message persistence side effects.
4. Add focused migration/helper/model, live app, offline-inbox, fake-network, and Go received-event tests.
5. Run focused and canonical groups gates, then update closure docs only after all MS-002 evidence passes.

## exact tests and gates to run

- `go test ./node -run 'TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch' -v` from `go-mknoon`
- `flutter test --no-pub test/core/database/migrations/061_group_message_transport_peer_id_test.dart`
- `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path creates all tables with correct schema'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'MS002'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'MS002'`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'MS002'`
- `flutter test --no-pub test/features/groups/application/*group_message*_test.dart`
- `./scripts/run_test_gates.sh groups`
- `flutter test --no-pub test/features/groups/integration`
- `git diff --check`

## done criteria

- Accepted messages store `transportPeerId`; mismatched transport/claimed sender payloads are rejected before save.
- Offline inbox replay uses relay envelope `from` as the transport binding and preserves/rejects accordingly.
- Source matrix MS-002 row is `Covered`.
- `test-inventory.md` MS-002 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, ordered session row, and closure progress record MS-002 as accepted/Covered.

## scope guard

Do not add an account/device registry, new key-package protocol, UI device-management surface, or real-device transport harness under MS-002. This session closes the shipped libp2p Peer ID transport binding and durable message authorship facts.

## Dirty Worktree Snapshot

Captured at `2026-05-01T07:03:40+02:00`: the tree already contains prior rollout changes in docs, Go node tests, Flutter group code/tests, and untracked prior session plan files. MS-002 execution is scoped to the files listed above unless focused tests expose another row-owned identity-binding gap.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T07:15:00+02:00 | Local executor completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/bridge/events.go`; `lib/core/database/migrations/061_group_message_transport_peer_id.dart`; `lib/main.dart`; `lib/features/groups/domain/models/group_message.dart`; `lib/core/database/helpers/group_messages_db_helpers.dart`; `lib/features/groups/domain/repositories/group_message_repository_impl.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/send_group_message_use_case.dart`; MS-002 focused tests and fakes | Implemented durable transport Peer ID binding for shipped group-message authorship: Go received events expose the validator-bound transport Peer ID, Dart live/replay paths reject nonempty transport/sender mismatches before persistence or event-log side effects, accepted messages persist `transportPeerId`, offline inbox uses relay `from` as transport origin, and migration/model/helper/repository paths surface `transport_peer_id`. | Run focused and broad gates, then close source docs only if all evidence passes. |
| 2026-05-01T07:15:00+02:00 | Local QA accepted | Focused Go proof; migration/helper/repository tests; fresh migration-chain schema check; focused handle-incoming/drain-inbox/fake-network MS002 tests; full group-message application wildcard; groups gate; full groups integration; `git diff --check` | Accepted. Commands passed: `go test ./node -run 'TestBuildGroupMessageReceivedEvent_IncludesQuotedMessageId|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch' -v`; `flutter test --no-pub test/core/database/migrations/061_group_message_transport_peer_id_test.dart`; `flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart`; `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart`; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name 'Fresh install path creates all tables with correct schema'`; focused MS002 app/integration tests; `flutter test --no-pub test/features/groups/application/*group_message*_test.dart` (`+213`); `./scripts/run_test_gates.sh groups` (`+99`); `flutter test --no-pub test/features/groups/integration` (`+121`); `git diff --check`. | Update source matrix, inventory, and breakdown to `Covered`/accepted. |

## Final Execution Verdict

Accepted on 2026-05-01. MS-002 is covered for the shipped trusted-private identity unit: the libp2p transport Peer ID is now the durable message transport/device identity, accepted live and offline-inbox messages persist that verified Peer ID, and spoofed transport/sender mismatches fail before persistence. Supporting `group-real-network-nightly` was not run because relay/device environment variables are unset; separate account/device registry and per-device key-package semantics remain outside MS-002.
