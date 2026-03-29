# Session 32 Plan — Make 1:1 Direct/Relay Icons Reflect Actual Message Transport

## Real Scope

What changes in this session:

- make new outgoing 1:1 message rows persist `direct` vs `relay` from the
  actual chat stream transport when the send path goes through Go/libp2p
- make new incoming 1:1 message rows persist `direct` vs `relay` from the
  actual inbound chat stream transport instead of inferring from current peer
  state alone
- keep `wifi`, `local`, and `inbox` semantics unchanged
- close the known `_tryRelayProbeSend` direct-vs-relay labeling mismatch as part
  of the same transport-truth seam
- add direct regressions that prove mixed direct+relay connection state no
  longer makes message icons untrustworthy

What does not change in this session:

- no redesign of actual routing preference, dialing policy, or retry policy
- no changes to group, announcement, or post icon semantics as a product goal
- no DB migration for legacy rows already stored as `reuse`
- no removal of the legacy `reuse` UI fallback
- no product-scope UI redesign, new icons, or new user settings

---

## Closure Bar

This session is sufficient when all of the following are true:

- new outgoing 1:1 rows use the actual stream transport for `direct` vs
  `relay`, not a guess from current connection state, whenever the send goes
  through Go/libp2p
- new incoming 1:1 rows use the actual inbound stream transport for `direct`
  vs `relay`, not a guess from current connection state, whenever the message
  came through the Go bridge
- mixed peer state with both direct and relay connections no longer forces a
  relay icon when the actual message transport was direct
- successful relay-probe sends no longer persist `direct` when the transport
  was actually relay
- `wifi`, `local`, and `inbox` remain correct and unchanged
- legacy fallback behavior remains available only for older untagged bridge
  payloads or legacy rows, not as the primary truth path for new messages

---

## Source Of Truth

Authoritative sources for this session:

- current code and tests in the 1:1 send path, P2P bridge/service, and
  conversation UI
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/bridge/events.go`

Conflict rules:

- current code and tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on named-gate
  membership
- this plan is the active execution contract unless repo evidence proves a step
  stale or wrong

---

## Session Classification

`implementation-ready`

Why:

- the current repo proves the problem is real and user-visible
- the direct/relay mismatch comes from identifiable repo-local seams
- Go already has stream access and a circuit-address helper, so the plan can
  tag actual transport without inventing a new transport architecture
- the bridge and Flutter models already support additive fields cleanly

---

## Exact Problem Statement

Today the direct-vs-relay message icon is not trustworthy for 1:1 chat:

- outgoing reuse-fast-path sends currently persist `direct` or `relay` from
  Flutter-side connection-state inference, not from the exact stream transport
- incoming messages usually arrive without a transport tag from Go, so Flutter
  falls back to `_inferTransportForPeer`, which returns `relay` if any matching
  connection has `/p2p-circuit`
- if both direct and relay connections exist for the same peer, the incoming
  icon can show relay even when the actual message used direct
- `_tryRelayProbeSend` still persists `direct` on success, even though that
  path is relay-mediated

What must improve:

- the direct vs relay icon on new 1:1 message rows must represent the actual
  message transport, not a best-effort state guess
- send and receive must use the same truth model for direct vs relay

What must stay unchanged:

- the app may still keep multiple peer connections alive
- the routing behavior itself does not need to change just to make icons honest
- local WiFi and inbox semantics stay as they are

---

## Files And Repos To Inspect Next

Production files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/features/p2p/domain/models/send_message_result.dart`
- `lib/features/p2p/domain/models/chat_message.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `go-mknoon/node/node.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/events.go`

Tests:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/bridge/p2p_bridge_client_test.dart`
- `test/features/p2p/domain/models/send_message_result_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `go-mknoon/node/send_message_recovery_test.go`
- `go-mknoon/node/node_test.go`
- `go-mknoon/bridge/bridge_test.go`

Infra / gate files:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

---

## Existing Tests Covering This Area

Already present:

- `send_chat_message_use_case_test.dart` now proves reuse-fast-path persistence
  for pure `direct`, `relay`, and `local`
- `p2p_service_impl_test.dart` proves incoming transport inference for pure
  direct-only and relay-only connection state
- `handle_incoming_chat_message_use_case_test.dart` proves a supplied transport
  value is persisted to `ConversationMessage`
- `letter_card_test.dart` already proves icon mapping for `direct`, `relay`,
  `wifi`, `local`, `inbox`, and legacy `reuse`
- `feed_wired.dart` still enters `send_chat_message_use_case.dart`, so feed is
  in the blast radius even though the icon itself renders in conversation UI

Still missing:

- proof that explicit Go-provided transport wins over conflicting mixed peer
  state
- proof that outgoing reuse sends persist actual stream transport rather than
  Flutter-side state inference when both direct and relay connections exist
- proof that relay-probe success persists `relay`
- Go-side proof that incoming `message:received` and bridge `message:send`
  expose transport additively

Current stale behavior pinned by code:

- `go-mknoon/bridge/events.go` documents `message:received` without transport
- `send_chat_message_use_case.dart` relay-probe success still returns
  `via: 'direct'`
- `p2p_service_impl.dart` incoming fallback still chooses relay if any
  connection multiaddr contains `/p2p-circuit`

---

## Regression / Tests To Add First

Add these proofs before implementation:

1. `go-mknoon/node/node_test.go` and/or `go-mknoon/bridge/bridge_test.go`
   - inbound `message:received` event includes `transport: 'direct'` for a
     non-circuit stream
   - inbound `message:received` event includes `transport: 'relay'` for a
     circuit stream
   - `message:send` response includes `transport`

2. `test/core/services/p2p_service_impl_test.dart`
   - explicit incoming `msg.transport` from Go wins over conflicting mixed peer
     connection state
   - mixed direct+relay connection state no longer defaults to relay when the
     incoming message itself is tagged `direct`

3. `test/features/conversation/application/send_chat_message_use_case_test.dart`
   - reuse-fast-path send persists `sendResult.transport` when provided
   - relay-probe success persists `relay` when `sendResult.transport == 'relay'`
   - fallback to state inference remains only when `sendResult.transport` is
     absent

4. `test/core/bridge/p2p_bridge_client_test.dart` and
   `test/features/p2p/domain/models/send_message_result_test.dart`
   - additive transport field is parsed/preserved without breaking current ACK
     semantics

These are the minimum regressions that prove icon truth for the seam you
described without bundling unrelated transport behavior changes.

---

## Step-By-Step Implementation Plan

1. Confirm the current stale seams in code:
   - `message:received` bridge events omit transport
   - `message:send` bridge responses omit transport
   - `_tryRelayProbeSend` still returns `via: 'direct'`
   - incoming fallback transport inference prefers relay on any circuit match

2. Add the direct regressions first:
   - Go tests for emitted send/receive transport
   - Flutter tests for mixed-state precedence and relay-probe correction

3. Add a narrow Go helper that classifies the actual stream transport from the
   opened/inbound libp2p stream connection:
   - `/p2p-circuit` => `relay`
   - otherwise => `direct`

4. Use that helper in `go-mknoon/node/node.go`:
   - tag inbound `message:received` events with transport
   - include transport in the bridge-facing `SendMessage` result used by
     `message:send`

5. Update the bridge contract additively:
   - `go-mknoon/bridge/events.go`
   - `go-mknoon/bridge/bridge.go`
   - `lib/core/bridge/p2p_bridge_client.dart`

6. Update Flutter models additively:
   - extend `SendMessageResult` with optional transport
   - map bridge `transport` through `P2PServiceImpl.sendMessageWithReply`
   - keep legacy fallback behavior when transport is absent

7. Update `send_chat_message_use_case.dart` to prefer actual send-result
   transport for non-local Go/libp2p sends:
   - reuse fast path
   - direct discover/dial/send path
   - relay-probe success path
   - keep `local` and `inbox` explicit

8. Leave incoming persistence flow unchanged except that it now receives a
   trustworthy transport tag from `P2PServiceImpl` when Go provides one.

9. Make the new regressions pass, then stop.

Stop rule inside implementation:

- if repo evidence shows the Go stream layer cannot expose a trustworthy
  direct-vs-relay classification from the actual stream connection, stop and
  reclassify the plan as `evidence-gated` rather than inventing another
  heuristic

---

## Risks And Edge Cases

- the same peer may have both direct and relay connections alive at once; the
  actual message transport must win over current-state inference
- relay-probe success must not keep stamping `direct`
- local WiFi messages must stay `wifi` / `local` and not be overwritten by Go
  transport tags
- inbox handoff must stay `inbox` even if the attempted live send transport was
  direct or relay
- legacy or older untagged bridge payloads still need a safe fallback path
- additive `transport` on `SendMessageResult` must not break other shared
  `sendMessageWithReply` call sites
- feed-originated inline 1:1 send still shares the send path and must not
  regress while this seam is corrected

---

## Exact Tests And Gates To Run

Direct suites:

- `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/core/bridge/p2p_bridge_client_test.dart`
- `flutter test test/features/p2p/domain/models/send_message_result_test.dart`
- `cd go-mknoon && go test ./bridge ./node`

Named gates:

- `./scripts/run_test_gates.sh 1to1`
  - required because this changes shared 1:1 send/listener transport truth
- `./scripts/run_test_gates.sh feed`
  - required because `feed_wired.dart` still enters `send_chat_message_use_case.dart`
- `./scripts/run_test_gates.sh baseline`
  - required because Flutter production files change
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
  - required because this changes the Flutter/Go bridge transport-label
    contract and `p2p_service_impl.dart`

Not required by default:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh posts`

---

## Known-Failure Interpretation

- use `Test-Flight-Improv/test-gate-definitions.md` as the source of truth for
  named-gate scope and known failures
- the `1to1`, `feed`, and `baseline` gates are currently treated as green; any
  new failure there is a blocker unless clearly shown to be unrelated and
  pre-existing
- the `transport` gate was last revalidated on 2026-03-26; any new failure in
  the bridge/transport gate is a blocker unless clearly shown to be unrelated
  and pre-existing
- any failure in `go test ./bridge ./node` is a blocker for this session
  because the plan changes those packages directly
- unrelated red tests outside the direct suites and required named gates are
  not Session 32 regressions unless this change clearly caused or widened them

---

## Done Criteria

- Go emits actual `direct` vs `relay` transport for inbound 1:1 chat messages
- Go returns actual `direct` vs `relay` transport for bridge `message:send`
  responses
- Flutter persists outgoing 1:1 `direct` vs `relay` from actual send-result
  transport when available
- Flutter persists incoming 1:1 `direct` vs `relay` from actual Go event
  transport when available
- mixed direct+relay peer state no longer makes new message icons misleading
- relay-probe success no longer persists `direct`
- `wifi`, `local`, `inbox`, and legacy `reuse` fallback remain correct
- required direct suites, Go package tests, and named gates are green

---

## Scope Guard

- do NOT redesign connection selection or transport preference policy
- do NOT broaden into connection-status indicator work outside message rows
- do NOT broaden into group, announcement, or posts product icon cleanup
- do NOT remove the legacy `reuse` fallback or migrate old rows
- do NOT add a new metrics/dashboard program
- do NOT change delivery semantics just to make icon parity look cleaner

---

## Accepted Differences / Intentionally Out Of Scope

- older untagged bridge payloads may still fall back to inference; this session
  is about making new rows trustworthy, not forcing a migration boundary
- this session does not promise that every non-chat feature using
  `sendMessageWithReply` will surface a transport icon
- connection availability and relay health indicators elsewhere in the app are
  separate concerns from per-message icon truth

---

## Dependency Impact

- this session should land before any broader message-icon cleanup so later UI
  work can rely on emitted transport truth instead of state inference
- once this lands, future 1:1 reliability or transport-label work should prefer
  actual emitted transport over connection-state heuristics
- if the plan changes and Go transport tagging is deferred, any later UI/icon
  work should also pause rather than stacking more heuristics on top of the
  current mismatch
