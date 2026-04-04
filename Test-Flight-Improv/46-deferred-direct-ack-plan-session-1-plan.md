# Session 1 Plan - Deferred direct ACK protocol and receiver confirmation path

## Final verdict

`implementation-ready`

Current repo evidence keeps Report `46` scoped to one shared receive/ack seam:

- `go-mknoon/node/node.go` still writes `{"ack":true}` immediately inside
  `handleIncomingMessage(...)` before Flutter has classified or persisted the
  incoming payload.
- `go-mknoon/node/config.go` and `go-mknoon/node/feature_flags.go` do not yet
  expose a deferred-direct-ack timeout/flag contract.
- `go-mknoon/bridge/bridge.go`, `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`,
  `ios/Runner/GoBridge.swift`, and `macos/Runner/MainFlutterWindow.swift` do
  not yet expose a receiver-confirmation method back into Go.
- `lib/features/p2p/domain/models/chat_message.dart` does not preserve a
  confirmation nonce from the bridge event payload.
- `lib/core/bridge/go_bridge_client.dart` currently routes push events straight
  to `onMessageReceived` and `send(...)` encodes `payload` maps itself, so the
  Session `1` confirmation helper must use the normal map payload contract,
  not a pre-encoded JSON string inside `payload`.
- `lib/features/conversation/application/chat_message_listener.dart` has many
  early returns from `processIncomingMessage(...)`; confirmation must be
  centralized so each terminal branch resolves the nonce exactly once instead
  of only the happy path.

This session should therefore land the full nonce-based confirmation seam in
one pass across Go, native bridge routing, Dart bridge helpers, the chat model,
and the receive listener, then add the focused regressions that prove sender
ACK now depends on receiver confirmation instead of raw transport read.

## Final plan

### real scope

- Add deferred direct ACK infrastructure in `go-mknoon/node`:
  - pending nonce state
  - bounded wait/resolve helpers
  - timeout constant
  - rollout feature flag defaulting to enabled
  - `handleIncomingMessage(...)` gating ACK on receiver confirmation or timeout
- Export one Go bridge method for resolving direct-message confirmations and
  wire it through Android, iOS, and macOS native bridge method switches.
- Extend `ChatMessage` with `confirmNonce`.
- Add one Dart-side helper that sends the confirmation command through the
  repo's existing `{cmd, payload: <map>}` bridge contract.
- Centralize nonce confirmation in the Dart receive path so every terminal
  branch resolves once:
  - `chatMessage`
  - `duplicate`
  - `blockedSender`
  - `missingMlKemSecret`
  - `decryptionFailed`
  - `unknownSender`
  - `editMissingOriginal`
  - `notChatMessage`
  - parse/non-chat failure branches scoped by the breakdown
- Add focused Go and Dart regressions for happy-path confirm, timeout/no
  confirm, false confirm, duplicate confirm, and listener branch handling.

### closure bar

- Direct incoming 1:1 chat no longer sends sender-visible ACK merely because
  Go successfully read the frame.
- A receiver-side stored or duplicate terminal outcome confirms the nonce and
  allows ACK; retryable or unresolved receive outcomes do not.
- The receive path resolves each nonce at most once from a centralized Dart
  location despite the current early-return structure.
- Bridge routing works on Android, iOS, and macOS using the repo's existing
  method-channel JSON contract.
- The direct regressions below pass, plus the required named gates.
- Session `1` does not overclaim DB-backed durability for non-chat direct
  message classes unless code evidence during execution proves that broader
  claim.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
  - `Test-Flight-Improv/46-deferred-direct-ack-plan.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.
- Verified seam files:
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/feature_flags.go`
  - `go-mknoon/node/transport_label_test.go`
  - `go-mknoon/bridge/bridge.go`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/features/p2p/domain/models/chat_message.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `test/core/bridge/go_bridge_client_test.dart`
  - `test/core/bridge/p2p_bridge_client_test.dart`
  - `test/features/p2p/domain/models/chat_message_test.dart`
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`

### session classification

`implementation-ready`

### exact problem statement

- The current Go receive path acknowledges a direct incoming 1:1 message before
  Flutter has persisted it or even decided whether the payload is retryable,
  duplicate, decryptable, or actionable.
- That lets sender-visible `delivered` escape across EventChannel loss,
  backgrounding, listener exceptions, or retryable receive failures with no
  recovery path.
- The fix is not a full synchronous Go<->Flutter redesign. The minimal truthful
  contract is nonce-based deferred confirmation within the existing async
  bridges, with sender-side fallback to the already-closed inbox path when
  confirmation does not happen in time.

### files and repos to inspect next

- Go production:
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/feature_flags.go`
  - `go-mknoon/bridge/bridge.go`
- Native bridge routing:
  - `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`
  - `ios/Runner/GoBridge.swift`
  - `macos/Runner/MainFlutterWindow.swift`
- Flutter production:
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/features/p2p/domain/models/chat_message.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- Direct tests:
  - `go-mknoon/node/transport_label_test.go`
  - `go-mknoon/node/node_test.go`
  - `go-mknoon/bridge/bridge_test.go`
  - `test/core/bridge/go_bridge_client_test.dart`
  - `test/core/bridge/p2p_bridge_client_test.dart`
  - `test/features/p2p/domain/models/chat_message_test.dart`
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`

### existing tests covering this area

- `go-mknoon/node/transport_label_test.go` already exercises
  `handleIncomingMessage(...)` enough to anchor new deferred-ACK tests in the
  same seam.
- `test/features/conversation/application/chat_message_listener_test.dart`
  already covers multiple terminal receive outcomes such as
  `missingMlKemSecret` and `editMissingOriginal`.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  already proves duplicate, unknown-sender, decryption-failure, and non-chat
  classification outcomes.
- `test/features/p2p/domain/models/chat_message_test.dart` already pins the
  model serialization/equality contract and is the right home for nonce field
  coverage.
- `test/core/bridge/go_bridge_client_test.dart` and
  `test/core/bridge/p2p_bridge_client_test.dart` already prove bridge command
  routing and request-shape behavior.
- Missing today:
  - no Go regression proving timeout/no-confirm leaves the sender unacked
  - no bridge regression for `confirmDirectMessage`
  - no Dart regression proving confirmation happens from every relevant terminal
    listener branch using the normal map payload contract

### regression/tests to add first

- Add the Go direct regression first for the escaped seam:
  receiver-side no-confirm / timeout must not produce sender-visible ACK.
- Add focused Go tests for:
  - happy-path confirm -> ACK written
  - timeout/no-confirm -> stream reset/no ACK
  - false confirm -> no ACK
  - duplicate/late confirm does not leak or double-resolve
- Add focused Dart tests for:
  - `ChatMessage.fromJson` preserves `confirmNonce`
  - bridge helper sends `message:confirm` with `payload` as a map
  - listener confirms `ok=true` for stored and duplicate/accepted-drop paths
  - listener confirms `ok=false` for retryable/reject paths in scope
  - non-chat direct event handling stays on the accepted best-effort model in
    scope without broadening into new durability claims

### step-by-step implementation plan

1. Re-read the live dirty worktree for the files above and merge carefully with
   unrelated in-flight edits, especially in `go-mknoon/node/node.go`,
   `android/.../GoBridge.kt`, `ios/Runner/GoBridge.swift`, and
   `macos/Runner/MainFlutterWindow.swift`.
2. Add the Go pending-confirmation state plus timeout constant/feature flag.
3. Refactor `handleIncomingMessage(...)` so direct ACK is deferred behind the
   nonce confirmation path while the legacy immediate-ACK path stays available
   behind the feature flag.
4. Export and wire the `confirmDirectMessage` bridge method through Go and all
   native bridge switches.
5. Extend `ChatMessage` and the Dart bridge helpers with nonce-aware command
   support using the normal map payload contract.
6. Centralize confirmation in `ChatMessageListener.processIncomingMessage(...)`
   so every terminal branch resolves the nonce exactly once, without appending
   ad hoc calls to scattered return sites.
7. Add the direct Go/Dart regressions listed above.
8. Run the exact direct tests and named gates below.
9. Update the Session `1` ledger in
   `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md` after
   execution/closure confirms the landed result.

### risks and edge cases

- Dirty-worktree risk: relevant files already have unrelated local edits; do
  not revert them or assume a clean base.
- Concurrency risk: pending-confirm map/channel cleanup must not leak or double
  close on timeout vs late confirmation.
- Contract risk: `GoBridgeClient.send(...)` JSON-encodes `payload`, so the new
  helper must pass a map, not a JSON string nested inside `payload`.
- Receive-path risk: current listener control flow has many early exits; a
  happy-path-only confirm call would recreate the false-delivered seam.
- Scope risk: non-chat direct messages may stay on best-effort confirmation in
  this session; do not broaden into a new durability architecture for those
  classes without fresh evidence.
- Lifecycle risk: if execution ends up touching resume/reconnect/bootstrap
  wiring rather than staying on the direct receive contract, the transport gate
  becomes mandatory instead of conditional.

### exact tests and gates to run

- Direct tests:
  - `cd go-mknoon && go test ./node ./bridge`
  - `flutter test test/core/bridge/go_bridge_client_test.dart`
  - `flutter test test/core/bridge/p2p_bridge_client_test.dart`
  - `flutter test test/features/p2p/domain/models/chat_message_test.dart`
  - `flutter test test/features/conversation/application/chat_message_listener_test.dart`
  - `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` only if execution broadens into
    resume/reconnect/inbox-drain/bootstrap wiring

### known-failure interpretation

- There is no accepted exemption for a sender receiving ACK after the receiver
  never confirms terminal handling; that remains the exact escaped seam.
- Pre-existing unrelated local changes or unrelated flaky tests must not be
  misclassified as Session `1` regressions unless the touched seam or required
  gate proves a real connection.
- If `transport` fails only after this session broadens into lifecycle wiring,
  keep that as in-scope; otherwise do not broaden just to chase unrelated
  transport flakiness.

### done criteria

- The direct receive path only ACKs after receiver confirmation or accepted
  scoped best-effort handling for the non-chat classes intentionally left
  unchanged.
- Timeout/no-confirm leaves sender unacked so fallback/retry semantics can
  engage.
- The nonce field survives Go -> native -> Dart event flow.
- Centralized listener confirmation covers the in-scope terminal branches
  exactly once.
- The direct tests above pass, plus `1to1` and `baseline`, with `transport`
  run only if the landed changes require it.
- Session `1` closure notes can truthfully say the false-delivered seam is
  closed without overclaiming broader protocol redesign.

### scope guard

- Do not redesign sender-visible status semantics beyond preventing false
  direct `delivered`.
- Do not invent a synchronous Go->Flutter->Go architecture.
- Do not broaden into group, announcement, or general notification work.
- Do not claim non-chat direct-message DB durability unless code evidence in
  this session truly lands it.
- Do not reopen Session `2` acceptance/closure work inside Session `1`.

### accepted differences / intentionally out of scope

- Non-chat direct messages may remain on an accepted lighter confirmation model
  in Session `1`.
- The session does not add read receipts or change `delivered` into anything
  stronger than ACK or inbox-backed delivery.
- The session does not require new DB migrations, inbox redesign, or a new
  transport architecture.

### dependency impact

- Session `2` depends on Session `1` landing a coherent deferred-ACK seam plus
  runnable direct/gate evidence.
- If Session `1` broadens materially into lifecycle/bootstrap wiring, Session
  `2` must inherit that expanded evidence set and run the transport gate.
