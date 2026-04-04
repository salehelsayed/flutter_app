# Session 1 Plan: Eliminate False Notifications From Deferred Direct ACK Timeout

## Final verdict

`ready_to_execute`

## Final plan

### 1. real scope

- Fix the direct-chat reliability gap where receiver-side processing can succeed
  after Go's deferred-ACK timeout, causing the sender to inbox-store the same
  message and potentially trigger a false push notification.
- Keep the fix inside Flutter client transport orchestration and durable local
  staging.
- Reuse the existing `message:confirm` bridge command and the existing
  `InboxStagingRepository` replay contract.
- Preserve the sender-side inbox safety net for true transport failure and for
  any path that cannot durably stage the direct copy on the receiver.
- Explicit non-goals:
  changing the Go deferred-ACK protocol again, adding relay/server changes,
  redesigning chat listener result semantics, or introducing a new delivery
  receipt protocol.

### 2. closure bar

- A direct incoming `chat_message` carrying `confirmNonce` must be durably
  staged on the receiver before Flutter sends `message:confirm ok=true`.
- Once staged, that direct message must be processed through the same
  committed/retryable/rejected replay contract already used for recovered inbox
  rows.
- If processing commits, the staged row must be deleted.
- If processing is retryable, the staged row must remain recoverable with the
  exact retry reason.
- If durable staging is unavailable, the system must fall back to the existing
  raw-stream path rather than silently dropping the direct message.
- Existing recovered-inbox behavior and chat listener confirmation tests must
  keep passing.

### 3. source of truth

- Production files:
  `lib/core/services/p2p_service_impl.dart`
  `lib/core/inbox/inbox_staging_entry.dart`
  `lib/core/inbox/inbox_staging_repository.dart`
  `lib/core/bridge/p2p_bridge_client.dart`
  `lib/main.dart`
- Existing behavior references:
  `go-mknoon/node/node.go`
  `go-mknoon/node/config.go`
  `lib/features/conversation/application/chat_message_listener.dart`
  `lib/features/conversation/application/send_chat_message_use_case.dart`
- Existing regression coverage:
  `test/core/services/p2p_service_impl_test.dart`
  `test/core/resilience/c2_ack_drop_test.dart`
  `test/features/conversation/application/chat_message_listener_test.dart`

### 4. session classification

- `bugfix`
- `reliability`
- `tdd_required`
- `transport_orchestration`

### 5. exact problem statement

- Go now defers direct ACK until Flutter confirms receiver-side terminal chat
  handling.
- The receiver-side path includes event dispatch, message routing, decrypt,
  contact validation, DB save, and the confirm round-trip back into Go.
- If that work exceeds `DirectConfirmTimeout`, Go drops the ACK and the sender
  immediately hands the same message to relay inbox fallback.
- That creates a bad split-brain outcome:
  the receiver may still finish processing the direct copy successfully, while
  the sender has already caused a second durable relay copy and likely a push
  notification.
- Existing tests intentionally encode ACK-loss -> inbox fallback as success, but
  they do not protect against false push/noise or receiver-owned late success.

### 6. fix strategy

- Treat direct ACK as "receiver has durably accepted responsibility", not
  "receiver finished all chat business logic."
- Implement that responsibility handoff on the receiver by:
  1. staging the incoming direct chat envelope in `InboxStagingRepository`
  2. sending `message:confirm ok=true` immediately after staging succeeds
  3. replaying the staged row through the existing recovered-inbox chat replay
     callback
  4. deleting or retaining the staged row according to the replay outcome
- If staging fails or the replay callback is unavailable, fall back to the
  current raw message-stream path so behavior does not regress into message loss
  for unsupported environments.

### 7. files to inspect and change

- `lib/core/services/p2p_service_impl.dart`
- `test/core/services/p2p_service_impl_test.dart`
- optionally `test/core/resilience/c2_ack_drop_test.dart` only if targeted
  service coverage proves insufficient

### 8. existing tests covering this area

- `test/core/services/p2p_service_impl_test.dart`
  already covers staged inbox replay, committed/retryable chat outcomes, and
  safe `retrieve_pending` behavior.
- `test/features/conversation/application/chat_message_listener_test.dart`
  already proves listener-side `message:confirm` semantics for the old raw
  direct path.
- `test/core/resilience/c2_ack_drop_test.dart`
  proves the sender-side ACK-loss fallback behavior but does not assert
  receiver-owned durable staging before ACK.

### 9. regressions/tests to add first

1. Add a failing service test:
   `direct chat with confirmNonce stages locally, confirms, and commits via replay callback`.
2. Add a second failing service test:
   `direct chat with confirmNonce keeps staged row retryable when replay callback asks for retry`.
3. Add a third service test if needed for scope safety:
   `without replay callback, direct chat still uses the legacy raw stream path and does not eagerly confirm`.

### 10. implementation plan

1. Extend `P2PServiceImpl` with a narrow direct-chat interception path for
   incoming messages that:
   - are incoming
   - decode as `chat_message`
   - carry a non-empty `confirmNonce`
   - have a configured recovered-chat replay callback
2. Build a durable staging entry from the direct message using the existing
   `InboxStagingEntry` model and store it through `InboxStagingRepository`.
3. After staging succeeds, call `message:confirm ok=true` immediately.
4. Replay the same direct message through the existing recovered-chat replay
   callback, but without reusing the nonce for a second listener-level confirm.
5. Reuse `_applyRecoveredInboxOutcome(...)` so direct staged chat uses the same
   committed/retryable/rejected semantics as recovered inbox chat.
6. If staging throws or the direct message cannot be staged safely, forward the
   raw message to `messageStream` exactly as today.
7. Run the targeted tests, then widen to the related chat listener and ACK-drop
   suites.

### 11. risks and edge cases

- The direct staging path must not also emit the raw message into
  `messageStream`, or chat processing will duplicate.
- The replay callback may throw because the rest of the app stack is not ready
  yet; in that case the staged row must remain retryable.
- Recovered direct rows will replay through the inbox-staging path later and may
  carry `transport: inbox`; that is acceptable for this session because the
  priority is durable ownership and notification correctness, not perfect
  transport provenance.
- The fallback path for environments without a replay callback must remain
  intact.

### 12. exact tests to run

- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- `flutter test test/core/resilience/c2_ack_drop_test.dart`
- `flutter analyze lib/core/services/p2p_service_impl.dart`

### 13. known-failure interpretation

- If the new service tests fail before implementation, that confirms the gap is
  still real.
- If the commit-path test fails after implementation, direct messages are not
  being durably owned before ACK.
- If the retryable-path test fails, the fix is ACKing too early without keeping
  a durable local recovery record.
- If the legacy fallback test fails unexpectedly, the new interception path is
  too broad and is altering unsupported environments.

### 14. done criteria

- Direct incoming chat messages with `confirmNonce` are staged locally before
  ACK.
- A staged direct chat can commit or stay retryable via the existing replay
  contract.
- The targeted tests pass.
- No Go or relay changes are required for the landed fix.
