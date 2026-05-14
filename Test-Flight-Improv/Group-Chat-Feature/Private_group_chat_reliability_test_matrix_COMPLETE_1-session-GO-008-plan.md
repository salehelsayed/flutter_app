# GO-008 Log Privacy Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 22:17 CEST - Local gap-closure pass selected GO-008 after GO-004 closure. Files inspected: source matrix GO-008 row, session-breakdown GO-008 row, `lib/core/bridge/go_bridge_client.dart`, `lib/core/utils/flow_event_emitter.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `test/core/bridge/go_bridge_client_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision: reclassify from evidence-only to `needs_code_and_tests` because raw `group_message:received` FLOW logging exposed full event payloads and the text sanitizer did not cover JSON-like sensitive fields embedded in diagnostic strings.

## Original Source Row

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GO-008 | Logs never include group keys, plaintext, or full sensitive payloads | Run all failure cases. | 1. Capture logs/events. 2. Search for plaintext/key/ciphertext policy violations. | No secret material or plaintext leaks. | P0 | Open | Required | Required | N/A | N/A | N/A | Privacy gate. |

## Reconciliation Verdict

GO-008 was repo-owned because the source row was still `Open`, no adjacent GO-008 plan existed, and concrete inspection found two local privacy gaps: raw Go bridge FLOW passthrough for `group_message:received` could include plaintext/media encryption details, and flow redaction did not handle JSON-like sensitive fields inside non-sensitive diagnostic strings. The row was closed with runtime sanitization plus exact native, bridge, send-use-case, drain-use-case, analyzer, race, and named gate proof.

## Device/Relay Proof Profile

- Profile: host-only privacy proof.
- Source matrix requires Unit and Integration and marks Smoke, Fake Network, and 3-Party E2E as N/A.
- No live device, simulator, relay, OS notification, or multi-relay proof is required for GO-008 closure.
- Supporting named gate: `./scripts/run_test_gates.sh groups`.

## Scope

Own exactly GO-008:

- Ensure bridge FLOW logs for incoming group messages keep delivery metadata but omit plaintext, media payloads, group keys, ciphertext, nonce, and arbitrary sensitive extras.
- Ensure diagnostic FLOW redaction catches JSON/key-value encoded sensitive fields in error strings and direct detail maps.
- Prove send retry payload logs and drain cursor-error logs omit protected plaintext/key/ciphertext/media material.
- Prove native failure diagnostics/logs omit plaintext, group keys, ciphertext, nonce, signatures, and sender private keys across decrypt, parse, and validation diagnostics.
- Update source matrix, breakdown, and test inventory only after concrete evidence exists.

## Out Of Scope

- Adding new product-visible privacy settings.
- Adding a device/relay scenario, because GO-008 device proof is N/A.
- Rewriting all existing log sites beyond row-owned group privacy surfaces.
- Treating GO-009 race detector closure as GO-008 evidence; GO-009 is closed separately.

## Owner Files

- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-008-plan.md`

## Required Validation

```sh
gofmt -w go-mknoon/node/pubsub_decryption_failure_test.go
dart format --set-exit-if-changed lib/core/utils/flow_event_emitter.dart lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
dart analyze lib/core/utils/flow_event_emitter.dart lib/core/bridge/go_bridge_client.dart lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
cd go-mknoon && go test ./node -run 'TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents' -count=1
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-008'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-008'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GO-008'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1
./scripts/run_test_gates.sh groups
git diff --check -- lib/core/bridge/go_bridge_client.dart lib/core/utils/flow_event_emitter.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart go-mknoon/node/pubsub_decryption_failure_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GO-008-plan.md
```

## Done Criteria

- Source row GO-008 is `Covered` with concrete code, file, test, and gate evidence.
- Bridge raw incoming group message FLOW logs include bounded metadata only.
- Diagnostic FLOW logs redact direct and JSON-like sensitive fields.
- Native failure diagnostics/logs do not expose plaintext, group keys, ciphertext, nonce, signatures, or sender private keys.
- Send retry and drain cursor-error privacy paths are covered by exact GO-008 tests.
- No `accepted_with_explicit_follow_up` is used for unresolved GO-008 gaps.

## Execution Evidence

- Runtime hardening:
  - `lib/core/bridge/go_bridge_client.dart` now maps raw `group_message:received` FLOW details to bounded metadata only: group, sender/device/transport ids, message id, key epoch, decrypt/delivery timing, text length, and media count. The normal app callback still receives the full message payload.
  - `lib/core/utils/flow_event_emitter.dart` now redacts a broader sensitive-key set, including plaintext, ciphertext, nonce, signatures, group/media keys, invite tokens, and JSON/key-value encoded sensitive fields inside diagnostic strings.
- Native proof:
  - `go-mknoon/node/pubsub_decryption_failure_test.go::TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents` captures native logs and event callbacks across decrypt failure, payload-parse failure, and validation rejection diagnostics and proves no protected plaintext, group keys, ciphertext, nonce, signature, or sender private key appears.
- Flutter bridge proof:
  - `test/core/bridge/go_bridge_client_test.dart::GO-008 group message raw flow logs metadata only without plaintext or sensitive payloads` proves `group_message:received` app callbacks still receive plaintext while FLOW logs omit text, media payloads, ciphertext, group keys, and media encryption metadata.
  - `test/core/bridge/go_bridge_client_test.dart::GO-008 diagnostic flow logs redact JSON-encoded sensitive payload strings` proves diagnostic streams and FLOW logs redact sensitive JSON-like values embedded in error strings and direct detail fields.
- App privacy proof:
  - `test/features/groups/application/send_group_message_use_case_test.dart::GO-008 EK-002 GI-035 pending inbox retry and flow logs omit protected plaintext` proves pending inbox retry flow logs omit protected plaintext, private invite state, media key, and media nonce fragments.
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GO-008 cursor error flow logs redact JSON payload plaintext and keys` proves cursor-error FLOW logs redact embedded plaintext, ciphertext, nonce, group key, media key, and multiaddr fragments.
- Race-gate dependency fixed separately under GO-009:
  - The required selected race command initially exposed repo-owned lifecycle races in `go-mknoon/node/node.go` and `go-mknoon/node/pubsub.go`; GO-009 owns that closure. The final selected race command passed after the GO-009 lifecycle fix.
- Passed validation:
  - `gofmt -w go-mknoon/node/pubsub_decryption_failure_test.go`
  - `dart format --set-exit-if-changed lib/core/utils/flow_event_emitter.dart lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`Formatted 5 files (0 changed)`)
  - `dart analyze ...` on GO-008 runtime/test owners (`No issues found!`)
  - `cd go-mknoon && go test ./node -run 'TestGO008FailureDiagnosticsDoNotLeakSensitiveLogsOrEvents' -count=1` (`ok github.com/mknoon/go-mknoon/node 1.171s`)
  - `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'GO-008'` (`+2 All tests passed`)
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GO-008'` (`+1 All tests passed`)
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GO-008'` (`+1 All tests passed`)
  - `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart` (`+73 All tests passed`)
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` (`+165 All tests passed`)
  - `cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1` (`ok github.com/mknoon/go-mknoon/node 94.663s`)
  - `./scripts/run_test_gates.sh groups` (`+159 All tests passed`)

## Final Verdict

GO-008 is accepted/closed. The source matrix row is `Covered` with runtime privacy hardening, exact native failure-diagnostic no-secret proof, exact Flutter bridge FLOW redaction proof, exact send/drain privacy proofs, analyzer, selected race gate, and named groups gate evidence. Residual-only: none. GO-009 is covered separately; continue from GO-012, the next unresolved P0 session.
