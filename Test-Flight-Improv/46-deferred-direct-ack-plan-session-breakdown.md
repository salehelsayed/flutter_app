# Decomposition artifact updated

## Recommended plan count

2

## Decomposition artifact

- artifact path: `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
- proposal or source doc path: `Test-Flight-Improv/46-deferred-direct-ack-plan.md`
- downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Overall closure bar

The direct 1:1 receive path must stop treating a transport-level read as durable delivery. After this rollout:

- a direct incoming 1:1 chat message is ACKed only after Flutter reaches a receiver-side terminal disposition for that nonce
- the identified loss seam is closed: EventChannel gaps, backgrounding, listener errors, or retryable receive failures no longer yield sender-visible delivered status without a recovery path
- when receiver-side confirmation does not happen in time, sender-side direct send remains unacked and falls back to inbox / retry semantics already covered by current 1:1 closure
- existing 1:1 closure stays honest: `delivered` still means transport ACK or inbox-backed delivery, not read receipt

## Source of truth

- Proposal: `Test-Flight-Improv/46-deferred-direct-ack-plan.md`
- Closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Regression strategy: `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current send / ack seam:
  - `go-mknoon/node/node.go`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/core/services/p2p_service_impl.dart`
- Current receive / bridge seam:
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/p2p/domain/models/chat_message.dart`
  - `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`
  - `ios/Runner/GoBridge.swift`
  - `macos/Runner/MainFlutterWindow.swift`

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | `Deferred direct ACK protocol and receiver confirmation path` | `implementation-ready` | `Test-Flight-Improv/46-deferred-direct-ack-plan-session-1-plan.md` | none | `accepted` | Accepted on `2026-04-03` after bounded local planning, execution, and closure fallback landed nonce-gated direct ACK plumbing across `go-mknoon/node`, `go-mknoon/bridge`, Android/iOS/macOS method routing, Dart bridge helpers, `ChatMessage.confirmNonce`, and centralized listener confirmation. Direct proofs passed in `cd go-mknoon && go test ./node ./bridge`, `flutter test test/core/bridge/go_bridge_client_test.dart`, `flutter test test/core/bridge/p2p_bridge_client_test.dart`, `flutter test test/features/p2p/domain/models/chat_message_test.dart`, `flutter test test/features/conversation/application/chat_message_listener_test.dart`, `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`, `./scripts/run_test_gates.sh 1to1`, and `./scripts/run_test_gates.sh baseline`. Stable 1:1 closure wording remains intentionally deferred to Session `2`. |
| `2` | `Acceptance, gate validation, and reliability closure update` | `acceptance-only` | `Test-Flight-Improv/46-deferred-direct-ack-plan-session-2-plan.md` | `1` | `accepted` | Accepted on `2026-04-03` after bounded local planning, execution, and closure fallback added a sender-side no-confirm acceptance proof in `go-mknoon/node/send_message_recovery_test.go`, an explicit `acked=false` inbox-handoff proof in `test/features/conversation/application/send_chat_message_use_case_test.dart`, and the stable 1:1 closure refresh in `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`. Direct proofs passed in `cd go-mknoon && go test ./node ./bridge`, `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`, `flutter test test/features/conversation/application/chat_message_listener_test.dart`, and `./scripts/run_test_gates.sh 1to1`. The first plain `./scripts/run_test_gates.sh baseline` attempt failed only because multiple Flutter targets were attached; the macOS-targeted rerun then exposed a real stale macOS binding/intermediate mismatch for `BridgeConfirmDirectMessage`, which was fixed by refreshing the macOS gomobile artifact and rerunning from a clean `build/macos`. After that recovery, `FLUTTER_DEVICE_ID=macos flutter test -d macos integration_test/loading_states_smoke_test.dart` passed and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. The final native-binding verifier then exposed a stale iOS gomobile export for the same method, so the rollout finished with `./scripts/ensure_go_ios_bindings.sh`, `bash ./scripts/ensure_go_android_bindings.sh`, and a clean `./scripts/verify_gomobile_bindings.sh all` pass to keep iOS, macOS, and Android wrappers aligned with the generated artifacts. No `transport` rerun was required because this rollout stayed on the direct receive/send contract and did not broaden into startup, resume, reconnect, or inbox-drain wiring. |

## Ordered session breakdown

### Session 1

- title: Deferred direct ACK protocol and receiver confirmation path
- session id: 1
- session classification: implementation-ready
- intended plan file: `Test-Flight-Improv/46-deferred-direct-ack-plan-session-1-plan.md`
- exact scope:
  - add nonce-based pending direct confirmation plumbing in `go-mknoon/node`
  - gate `handleIncomingMessage` ACK emission on receiver-side confirmation or timeout
  - export confirmation through `go-mknoon/bridge/bridge.go` and route it through Android / iOS / macOS native bridges
  - extend `ChatMessage` with `confirmNonce`
  - add Dart confirmation helper using the repo’s existing `payload: <map>` bridge contract
  - centralize confirmation resolution in the Dart receive path so every terminal branch resolves the nonce exactly once
  - preserve explicit negative confirmation for retryable or reject branches where sender must not see `delivered`
  - add focused Go and Dart regressions for happy-path confirm, timeout/no-confirm, false confirm, duplicate confirm, and listener branch handling
- why it is its own session:
  - the Go, bridge, native, model, and listener changes form one inseparable protocol slice; splitting them would leave a misleading half-implemented state with no standalone verification value
- likely code-entry files:
  - `go-mknoon/node/node.go`
  - `go-mknoon/node/config.go`
  - `go-mknoon/node/feature_flags.go`
  - `go-mknoon/bridge/bridge.go`
  - `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`
  - `ios/Runner/GoBridge.swift`
  - `macos/Runner/MainFlutterWindow.swift`
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `lib/features/p2p/domain/models/chat_message.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- likely direct tests/regressions:
  - new `go-mknoon/node` deferred-confirm unit tests
  - `test/features/conversation/application/chat_message_listener_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - targeted bridge/model tests for nonce parsing and confirmation helper contract
- likely named gates:
  - `1:1 Reliability Gate`
  - `Baseline Gate` because Flutter production code changes
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - this breakdown artifact ledger
- dependency on earlier sessions:
  - none
- execution-safety corrections that must be carried into the session plan:
  - the proposal’s `message:confirm` helper must use the repo’s normal map payload contract, not a pre-encoded JSON string
  - `ChatMessageListener.processIncomingMessage(...)` currently has many early returns, so nonce confirmation must be centralized rather than appended near one return site
  - non-chat direct messages may stay on an accepted best-effort confirmation model; Session 1 should not overclaim DB-backed durability for those message classes unless code evidence is added

### Session 2

- title: Acceptance, gate validation, and reliability closure update
- session id: 2
- session classification: acceptance-only
- intended plan file: `Test-Flight-Improv/46-deferred-direct-ack-plan-session-2-plan.md`
- exact scope:
  - validate that the reproduced loss seam is closed under the new direct-ack contract
  - run the named gates and direct suites required by the changed seam
  - run at least one receiver-background / no-confirm acceptance check that proves sender stays unacked and falls back instead of showing false delivered state
  - update the 1:1 closure reference with the new direct-ack contract and any accepted differences
  - update this breakdown artifact with final ledger and program verdict
- why it is its own session:
  - device-backed and closure work validates multiple code paths at once and should not be bundled into the implementation session where it would blur the code closure bar
- likely code-entry files:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
  - any direct regression file added in Session 1
- likely direct tests/regressions:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - targeted direct suite(s) for bridge / lifecycle / background receive timing if Session 1 touched those branches materially
  - manual or device-backed acceptance for backgrounded receiver / no-confirm fallback
- likely named gates:
  - `1:1 Reliability Gate`
  - `Baseline Gate`
  - `Startup / Transport Gate` only if Session 1 expands into resume / reconnect / inbox-drain / bootstrap wiring rather than remaining on the direct receive contract
- matrix/closure docs to update when done:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - this breakdown artifact ledger
- dependency on earlier sessions:
  - Session 1

## Why this is not fewer sessions

- One giant session would mix protocol implementation with device-backed acceptance and closure updates, which weakens the stop rule and makes it easier to declare the fix done without proving the reproduced seam is actually closed.
- Session 2 exists because the proposal changes user-visible delivery semantics and needs explicit acceptance and closure evidence, not just green unit tests.

## Why this is not more sessions

- Splitting Go protocol plumbing from Dart confirmation plumbing would be bookkeeping only; neither half leaves a truthful independently verifiable state.
- Splitting native bridge routing into another session would add cross-tree coordination overhead without yielding a distinct gate or closure bar.
- The current proposal is about one correctness seam, not multiple independent features.

## Regression and gate contract

- Follow `Test-Flight-Improv/14-regression-test-strategy.md` and `Test-Flight-Improv/test-gate-definitions.md`.
- Session 1 must add the direct regression first for the exact escaped seam: receiver-side no-confirm path must no longer produce sender-visible delivered status.
- Session 1 direct suites should cover:
  - Go deferred-confirm happy path
  - timeout / no-confirm
  - false confirm
  - duplicate confirm resolution
  - Dart confirmation branch coverage for `chatMessage`, `duplicate`, `missingMlKemSecret`, `decryptionFailed`, `unknownSender`, and parse / non-chat cases as scoped
- Session 2 must run:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` is conditional, not automatic. Run it only if execution broadens into resume / reconnect / inbox-drain / bootstrap wiring.

## Matrix update contract

- Reuse the existing stable closure doc `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Session 2 owns the closure update because it will have the final accepted implementation facts and regression evidence.
- No new matrix doc is needed.

## Downstream execution path

- Session 1 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Session 2 should next go through:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Structural blockers remaining

- none, once Session 1 planning explicitly incorporates the execution-safety corrections listed in the Session 1 entry

## Accepted differences intentionally left unchanged

- This rollout is sufficient for the identified 1:1 reliability seam even if non-chat direct messages remain on a lighter confirmation model.
- This rollout does not need to redesign sender-visible status semantics beyond keeping `delivered` tied to actual ACK or inbox-backed delivery.
- This rollout does not require a fully synchronous Go→Flutter→Go architecture; nonce-based deferred confirmation is sufficient if it closes the false-delivered seam.

## Exact docs/files used as evidence

- `Test-Flight-Improv/46-deferred-direct-ack-plan.md`
- `Test-Flight-Improv/46-deferred-direct-ack-plan-session-1-plan.md`
- `Test-Flight-Improv/46-deferred-direct-ack-plan-session-2-plan.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/verify_gomobile_bindings.sh`
- `scripts/ensure_go_ios_bindings.sh`
- `scripts/ensure_go_android_bindings.sh`
- `go-mknoon/node/node.go`
- `go-mknoon/node/config.go`
- `go-mknoon/node/feature_flags.go`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/p2p/domain/models/chat_message.dart`
- `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`
- `android/app/libs/GoMknoon.aar`
- `ios/Runner/GoBridge.swift`
- `ios/Runner/GoMknoon.xcframework`
- `macos/Runner/MainFlutterWindow.swift`
- `macos/Runner/GoMknoon.xcframework`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

- The proposal does address the identified escaped seam: it converts receiver-side non-persistence into sender-side non-ack, which re-enters the already-closed inbox reliability path.
- The decomposition keeps the protocol slice intact in Session 1 so execution is coherent.
- The decomposition keeps acceptance and closure explicit in Session 2 so the rollout does not stop at “code compiles” without proving the reproduced failure mode is closed.

## Program rollout ledger

- Breakdown artifact used:
  `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
- Spawned-agent isolation used:
  `yes` for planning, execution, closure, and final-acceptance attempts; the
  Session `1` planning/execution/closure steps and the Session `2`
  planning/closure steps no-progressed and were replaced with the single
  bounded local fallbacks allowed by the pipeline skill
- Sessions processed:
  `2/2`
- Sessions accepted:
  `2`
- Sessions accepted_with_explicit_follow_up:
  `0`
- Sessions blocked:
  `0`
- Sessions skipped_due_to_dependency:
  `0`
- Plan fallbacks used:
  `2`
- Execution fallbacks used:
  `1`
- Closure fallbacks used:
  `2`
- Final acceptance fallbacks used:
  `1`
- Final program acceptance verdict:
  `closed`
- Stable docs updated:
  `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  `Test-Flight-Improv/46-deferred-direct-ack-plan-session-breakdown.md`
  `Test-Flight-Improv/46-deferred-direct-ack-plan-session-2-plan.md`
- Final blocker note:
  none
