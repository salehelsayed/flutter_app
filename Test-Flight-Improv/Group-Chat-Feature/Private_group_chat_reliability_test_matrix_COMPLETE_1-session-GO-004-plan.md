# GO-004 Decryption Failures Repair Without Plaintext Exposure Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 21:49 CEST - Local plan created after GO-003 closure selected GO-004 as the next unresolved P0 row. Files inspected: source matrix GO-004 row, session-breakdown GO-004 row, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/utils/flow_event_emitter.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/core/bridge/go_bridge_client_test.dart`, and `test/features/groups/application/group_message_listener_test.dart`. Decision: production behavior already emitted and routed bounded decryption diagnostics and queued live key repair, but the row lacked exact GO-004 proof that diagnostics expose repair metadata only and do not render plaintext.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-004 | Decryption failures are surfaced for repair without exposing plaintext | Wrong epoch/key on receiver. | 1. Deliver wrong-key message. 2. Inspect events/logs. 3. Trigger repair. | Diagnostic includes epochs/group/sender but no plaintext/key; app can request key repair or resync. | P0 | Open | Required | Required | N/A | Recommended | N/A | pubsub.go:730-739. |

## Reconciliation Verdict

GO-004 was repo-owned because the matrix row was still `Open` and no adjacent GO-004 plan or exact row-named proof existed. Current production code already satisfied the behavior: native PubSub emits `group:decryption_failed` with group, sender, key epoch, local key epoch, error, and decrypt timing; the Flutter bridge sanitizes diagnostic payloads; and the group listener queues a pending key-repair placeholder/request without normal message delivery. Closure therefore required exact row-owned tests and evidence, not runtime code changes.

## Device/Relay Proof Profile

- Profile: host-only required evidence.
- Source matrix requires Unit and Integration, marks Smoke and 3-Party E2E as N/A, and marks Fake Network as Recommended.
- No live device, simulator, relay, OS notification, or multi-relay proof is required for GO-004 closure.
- Supporting named gate: `./scripts/run_test_gates.sh groups`.

## Scope

Own exactly GO-004:

- Add exact native proof that a receiver with the wrong local key emits `group:decryption_failed` metadata for repair and does not leak plaintext, group keys, ciphertext, nonce, signature, or sender private key.
- Add exact Flutter bridge proof that `group:decryption_failed` reaches `groupDiagnosticEventStream`, does not invoke group-message callbacks, and redacts sensitive diagnostic fields while preserving group/sender/epoch metadata.
- Add exact listener proof that a live decryption-failure diagnostic queues a pending key-repair placeholder and repair request without rendering plaintext or persisting sensitive fields.
- Update source matrix, breakdown, and test inventory only after concrete evidence exists.

## Out Of Scope

- Adding new key-repair protocol behavior beyond the existing pending live repair request.
- Adding a three-party/device harness scenario, because GO-004 3-Party E2E is N/A.
- Changing offline replay pending-key repair semantics, which are covered by GEK/ER rows.
- Broad log privacy sweeps across all failure cases, which are owned by GO-008.
- Changing validator rejection policy for wrong epoch, stale senders, or removed members.

## Owner Files

- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `go-mknoon/node/pubsub.go`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-004-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/pubsub_decryption_failure_test.go
dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart
dart analyze lib/core/bridge/go_bridge_client.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart
cd go-mknoon && go test ./node -run 'TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly|TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey|TestHandleGroupSubscription_EmitsDecryptionFailedEvent'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-004'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GO-004'
./scripts/run_test_gates.sh groups
git diff --check -- go-mknoon/node/pubsub_decryption_failure_test.go test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-004-plan.md
```

## Done Criteria

- Source row GO-004 is `Covered` with concrete native and Flutter file/test/gate evidence.
- Wrong-local-key receive path emits a bounded `group:decryption_failed` diagnostic with group, sender, key epoch, local key epoch, error, and decrypt timing.
- Diagnostics and bridge flow logs do not expose plaintext, group keys, ciphertext, nonce, signature, or sender private key.
- Flutter bridge routes the diagnostic to the diagnostics stream, not the normal group message callback.
- Group listener creates a pending live key-repair placeholder/request without rendering plaintext or persisting sensitive fields.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-004 gaps.

## Execution Evidence

- Native proof:
  - `go-mknoon/node/pubsub_decryption_failure_test.go::TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly` publishes a valid signed/encrypted group envelope while the receiver has a wrong local key at the same epoch, observes `group:decryption_failed`, and proves `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, AES-GCM error text, and non-negative `decryptMs`.
  - The same test asserts the diagnostic event stream does not contain the plaintext marker, actual group key, wrong group key, ciphertext, nonce, signature, or sender private key, and that no `group_message:received` or `group_reaction:received` event appears.
- Flutter bridge proof:
  - `test/core/bridge/go_bridge_client_test.dart::GO-004 group decryption failure diagnostic reaches repair stream without message callback` proves `group:decryption_failed` reaches `groupDiagnosticEventStream`, preserves repair metadata, redacts injected `plaintext`, `groupKey`, `ciphertext`, and `nonce`, and does not call `onGroupMessageReceived`.
  - `test/core/bridge/go_bridge_client_test.dart::GO-004 group diagnostic stream redacts sensitive payload fields` proves diagnostic redaction for ciphertext, nonce, peer id, secret key fragments, and multiaddr fragments while preserving group/sender/epoch metadata.
- App repair proof:
  - `test/features/groups/application/group_message_listener_test.dart::GO-004 live decryption failure creates repair placeholder and trigger without plaintext delivery` proves a diagnostic queues one `groupPendingKeyRepairStatusPendingKey` placeholder, stores one pending repair with sender/key epoch/error and no replay envelope, triggers `GroupKeyRepairRequest` with `groupKeyRepairReasonLiveDiagnostic`, and keeps injected plaintext/key/ciphertext markers out of placeholder text and repair error.
- Existing production surfaces verified:
  - `go-mknoon/node/pubsub.go::emitGroupDecryptionFailed` emits bounded metadata only.
  - `lib/core/bridge/go_bridge_client.dart` forwards `group:decryption_failed` through diagnostic routing.
  - `lib/core/utils/flow_event_emitter.dart::sanitizeFlowEventDetails` redacts plaintext, key material, ciphertext, nonce, peer ids, and address fragments.
  - `lib/features/groups/application/group_pending_key_repair_service.dart::queueLiveGroupDecryptionFailureRepair` creates live pending repair state and key-repair requests.
  - `lib/features/groups/application/group_message_listener.dart` handles diagnostics before normal message persistence.
- Passed validation:
  - `gofmt -w go-mknoon/node/pubsub_decryption_failure_test.go`
  - `dart format --set-exit-if-changed test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart` (`Formatted 2 files (0 changed)`)
  - `dart analyze lib/core/bridge/go_bridge_client.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/group_message_listener.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/group_message_listener_test.dart` exited 0 with one pre-existing info-level lint at `test/features/groups/application/group_message_listener_test.dart:4516:13`.
  - `cd go-mknoon && go test ./node -run 'TestGO004DecryptionFailureDiagnosticContainsRepairMetadataOnly|TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey|TestHandleGroupSubscription_EmitsDecryptionFailedEvent'` (`ok github.com/mknoon/go-mknoon/node 5.845s`)
  - `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-004'` (`+2 All tests passed`)
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GO-004'` (`+1 All tests passed`)
  - `./scripts/run_test_gates.sh groups` (`+159 All tests passed`)

## Final Verdict

GO-004 is accepted/closed. The source matrix row is `Covered` with exact native wrong-key diagnostic/no-secret proof, exact Flutter bridge diagnostic/redaction proof, exact listener live key-repair proof, and named groups gate evidence. Residual-only: none. Continue from GO-008, the next unresolved P0 session.
