# GO-003 Sender Status Distinguishes Validator Rejection By Recipients Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 21:32 CEST - Local plan created after GO-002 closure selected GO-003 as the next unresolved P0 row. Files inspected: source matrix GO-003 row, session-breakdown GO-003 row, prior GO-001/GO-002 closure plans, `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, `go-mknoon/node/config.go`, `go-mknoon/internal/group_envelope.go`, `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and adjacent GO-focused tests. Decision: GO-003 was repo-owned because PubSub validator rejection already protected recipients but no publisher-visible rejection/repair signal existed, leaving stale senders vulnerable to a permanent phantom `sent` row.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-003 | Sender status distinguishes validator rejection by recipients | Sender has stale config/key. | 1. Sender publishes stale envelope. 2. Recipients reject. 3. Sender receives/observes no ack. | System detects or repairs stale sender state; user gets honest failure/retry, not permanent phantom sent. | P0 | Open | Recommended | Required | N/A | Required | Required | PubSub has no recipient ACK; app needs repair signal. |

## Reconciliation Verdict

Recipient-side PubSub validation already rejected stale sender envelopes, but the rejection stayed local to validators. The publisher could successfully publish a stale envelope and persist the outgoing message as `sent` even though authorized recipients rejected it. That blocker was repo-owned: the native node needed a privacy-bounded validator-feedback path, the bridge needed to forward that diagnostic, and the app needed to bind it to the exact outgoing row without exposing plaintext or key material.

## Scope

Own exactly GO-003:

- Add a versioned recipient-to-publisher validator feedback stream for stale `group_message` envelopes that carry a top-level `messageId`.
- Emit a publisher-side diagnostic event that names group, message id, rejection reason, envelope type, key epoch, and a recipient identifier/hash without including plaintext, keys, ciphertext, or the envelope payload.
- Forward the diagnostic through Flutter bridge diagnostics.
- Mark the exact outgoing group message `failed` when a validator rejection arrives, preserve or synthesize retry wire-envelope metadata, and emit the updated row to the listener stream.
- Add exact Go, Flutter, criteria, and three-device proof for the stale-sender rejection flow.
- Update source matrix, session breakdown, and test inventory only after concrete proof exists.

## Out Of Scope

- Adding recipient delivery acknowledgements or read receipts.
- Changing validator authorization rules for stale, removed, or bad-signature senders.
- Marking unrelated outgoing messages failed when the diagnostic message id or group id does not match.
- Retrying automatically before the sender has repaired its stale group configuration/key.
- Recording plaintext, group keys, ciphertext, or full raw envelopes in diagnostics.

## Owner Files

- `go-mknoon/node/config.go`
- `go-mknoon/node/node.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_validation_feedback.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-003-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/group_validation_feedback.go go-mknoon/node/config.go go-mknoon/node/node.go go-mknoon/node/pubsub.go go-mknoon/node/protocol_version_test.go go-mknoon/node/pubsub_delivery_test.go go-mknoon/internal/group_envelope.go
dart format --set-exit-if-changed integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart test/integration/group_multi_party_device_criteria_test.dart lib/core/bridge/go_bridge_client.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart
dart analyze integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart lib/core/bridge/go_bridge_client.dart
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-003'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GO-003'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-003'
cd go-mknoon && go test ./node -run 'TestGO003StaleSenderValidationFeedbackReturnsToPublisher|TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators|TestGroupProtocolIDs_AreVersionedCurrentContracts'
./scripts/ensure_go_ios_bindings.sh
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/config.go go-mknoon/node/node.go go-mknoon/internal/group_envelope.go go-mknoon/node/pubsub.go go-mknoon/node/group_validation_feedback.go go-mknoon/node/protocol_version_test.go go-mknoon/node/pubsub_delivery_test.go lib/core/bridge/go_bridge_client.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart test/integration/group_multi_party_device_criteria_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-003-plan.md
```

Required relay-backed device proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario go003 -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

## Done Criteria

- Source row GO-003 is `Covered` only after exact Go, Flutter, criteria, named gate, and required relay-backed device proof pass.
- The publisher receives a validator-rejection diagnostic for its exact stale outgoing message id.
- The app marks that outgoing row `failed`, not phantom `sent`, and keeps retry envelope metadata available.
- Recipients still reject the stale sender envelope and render no stale plaintext.
- Diagnostics expose only bounded repair information and do not include plaintext, group keys, ciphertext, or raw envelope payloads.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-003 gaps.

## Execution Evidence

- Native implementation:
  - `go-mknoon/node/config.go` defines `GroupValidationFeedbackProtocol`, and `go-mknoon/node/node.go` registers the stream handler.
  - `go-mknoon/internal/group_envelope.go` carries top-level optional `messageId` so validator feedback can bind to the exact publisher row without decrypting payloads.
  - `go-mknoon/node/pubsub.go` sets that top-level message id during publish and sends validator feedback after local recipient-side `group:validation_rejected` events.
  - `go-mknoon/node/group_validation_feedback.go` opens a bounded feedback stream to the publisher, retries through peer recovery for relay-limited links, handles inbound feedback, validates local group membership, and emits `group:publish_validation_rejected`.
  - `go-mknoon/node/protocol_version_test.go::TestGroupProtocolIDs_AreVersionedCurrentContracts` pins the new feedback protocol.
  - `go-mknoon/node/pubsub_delivery_test.go::TestGO003StaleSenderValidationFeedbackReturnsToPublisher` proves Alice/Bob reject stale Charlie traffic, Charlie receives `group:publish_validation_rejected` for the exact message id/reason/epoch, and no stale plaintext is delivered.
- Flutter/app implementation:
  - `lib/core/bridge/go_bridge_client.dart` forwards `group:publish_validation_rejected` as a diagnostic event and flow log without treating it as an inbound message.
  - `lib/features/groups/application/group_pending_key_repair_service.dart::markOutboundGroupMessageRejectedByValidator` loads the exact outgoing row, requires matching group id and outgoing direction, marks it `failed`, preserves or synthesizes retry wire-envelope metadata, and emits `GROUP_OUTBOUND_VALIDATION_REJECTED`.
  - `lib/features/groups/application/group_message_listener.dart` applies that diagnostic before key-repair handling and emits the updated row.
  - `integration_test/group_multi_device_real_harness.dart` wires diagnostic events into the listener stack used by real-device harnesses.
  - `test/core/bridge/go_bridge_client_test.dart::GO-003 routes publish validation rejection diagnostics without message delivery` proves bridge routing.
  - `test/features/groups/application/group_message_listener_test.dart::GO-003 marks outgoing validator rejected message failed and retryable` proves app row update behavior.
- Device harness implementation:
  - `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` add `go003` scenario support and criteria requiring stale-sender validation feedback, failed sender status, retryable wire envelope, and no receiver plaintext.
- Passed validation:
  - `dart analyze integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart lib/core/bridge/go_bridge_client.dart` (`No issues found!`)
  - `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-003'` (`+1`)
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GO-003'` (`+1`)
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GO-003'` (`+1`)
  - `cd go-mknoon && go test ./node -run 'TestGO003StaleSenderValidationFeedbackReturnsToPublisher|TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators|TestGroupProtocolIDs_AreVersionedCurrentContracts'` (`ok github.com/mknoon/go-mknoon/node 5.349s`)
  - `./scripts/ensure_go_ios_bindings.sh` rebuilt `ios/Runner/GoMknoon.xcframework`.
  - `./scripts/run_test_gates.sh groups` (`+159`)
  - Relay-backed device proof passed with command above, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go003_71Ln1O`, run id `1778700408366`, role verdicts `gmp_1778700408366_alice_verdict.json`, `gmp_1778700408366_bob_verdict.json`, and `gmp_1778700408366_charlie_verdict.json`, and final result `go003 proof passed: go003 verdicts valid for alice, bob, charlie`.
  - `git diff --check` on GO-003 owner files plus closure docs passed.

## Final Verdict

GO-003 is accepted/closed. The source matrix row is `Covered` with exact native feedback proof, Flutter diagnostic/row-update proof, criteria proof, named groups gate, rebuilt iOS binding, and required relay-backed three-device proof. Residual-only: none. Continue from GO-004, the next unresolved P0 session.
