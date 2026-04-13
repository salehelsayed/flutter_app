# Final Verdict

`implementation-ready`

The duplicate `"Hashkobly wants to connect"` alerts are consistent with the
contact-request retry path, not the introduction path. Relay evidence from
`2026-04-12` shows the same sender storing two distinct `contact_request`
messages for the same recipient within seconds, and each store triggered its
own push. The smallest safe fix is:

1. make key-exchange repair retries non-user-facing at the relay push layer
2. collapse the duplicate resume-plus-reconnect retry triggers into one shared
   recovery path

Do not redesign the full contact bootstrap protocol for this session.

# Final Plan

## 1. Real Scope

Change:

- duplicate visible contact-request pushes caused by key-exchange repair retries
- overlap between `handleAppResumed()` and `KeyExchangeRetrier` that currently
  sends the same repair twice in one recovery burst
- regression coverage for sender intent, resume/reconnect overlap, relay push
  suppression, and end-to-end retry behavior

Do not change:

- first-time user-initiated contact requests from QR scan or explicit accept
  flows
- introduction behavior, intro routing, or Orbit/Feed intro follow-up logic
- generic relay dedupe architecture for all 1:1 envelopes

## 2. Closure Bar

This session is done when all of the following are true:

- a key-exchange retry for an existing contact does not generate a visible
  `"X wants to connect"` push
- one foreground recovery burst cannot emit two retry sends for the same
  missing-key contact just because both resume and reconnect paths fired
- explicit new contact requests still alert normally and preserve current route
  behavior
- tests pin the sender intent, relay suppression, resume/reconnect overlap, and
  end-to-end recovery behavior

## 3. Source Of Truth

Primary code:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/contact_request/application/key_exchange_retrier.dart`
- `lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart`
- `lib/features/contact_request/application/send_contact_request_use_case.dart`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`

Primary tests:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/features/contact_request/application/key_exchange_retrier_test.dart`
- `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
- `test/features/contact_request/application/key_exchange_retry_smoke_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `go-relay-server/inbox_test.go`
- `go-relay-server/inbox_dedup_test.go`

Gate source of truth:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

When these disagree with older prose, current code plus
`scripts/run_test_gates.sh` wins.

## 4. Session Classification

`implementation-ready`

## 5. Exact Problem Statement

The user-visible alert was initially reported as an intro problem, but the
actual copy in production is contact-request push copy:
`"<username> wants to connect"`.

Evidence:

- relay logs on `2026-04-12 18:05:51 UTC` and `18:05:57 UTC` stored two
  messages from the same sender to the same recipient and sent two pushes
  immediately after
- relay logs again on `2026-04-12 18:12:09 UTC` and `18:12:13 UTC` repeated
  the same store-plus-push pattern
- `sendContactRequest()` generates a fresh v2 `msgId` for every send
- `handleAppResumed()` calls `retryIncompleteKeyExchanges()` directly
- `KeyExchangeRetrier` schedules another retry 5 seconds after an
  offline-to-online transition
- relay dedupe only suppresses duplicate pending inbox entries with the same
  extracted message ID

User-visible behavior to improve:

- existing-contact key repair must not look like a new connection request
- one recovery burst must not create two alert-worthy sends

Behavior that must stay unchanged:

- real first-time contact requests still produce the current push and route
  behavior
- existing contact-request receiver logic still updates missing ML-KEM keys
  silently when the sender is already a contact

## 6. Files And Repos To Inspect Next

Production:

- `lib/features/contact_request/application/send_contact_request_use_case.dart`
- `lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart`
- `lib/features/contact_request/application/key_exchange_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `go-relay-server/inbox.go`

Tests:

- `test/features/contact_request/application/send_contact_request_use_case_test.dart`
- `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
- `test/features/contact_request/application/key_exchange_retrier_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/features/contact_request/application/key_exchange_retry_smoke_test.dart`
- `go-relay-server/inbox_test.go`
- `go-relay-server/inbox_dedup_test.go`

Test classification docs:

- `Test-Flight-Improv/test-gate-definitions.md`

## 7. Existing Tests Covering This Area

Already covered:

- `send_contact_request_use_case_test.dart` verifies envelope shape and v2 send
- `retry_incomplete_key_exchanges_use_case_test.dart` verifies eligible-contact
  filtering and retry counts
- `key_exchange_retrier_test.dart` verifies the debounce and state transitions
- `app_lifecycle_recovery_test.dart` verifies resume currently triggers one
  retry path
- `key_exchange_retry_flow_test.dart` verifies retry flow and envelope shape
- `key_exchange_retry_smoke_test.dart` verifies repeated retry behavior at a
  smoke level
- `handle_incoming_message_use_case_test.dart` and
  `contact_request_flow_test.dart` already prove existing-contact and duplicate
  request handling on the receiver side
- `go-relay-server/inbox_test.go` verifies contact-request push payload content
- `go-relay-server/inbox_dedup_test.go` verifies duplicate pending inbox
  entries do not fire a second push when the message ID matches

Missing:

- no test covers the overlap between resume-triggered retry and the delayed
  reconnect retry
- no test distinguishes first-time contact requests from key-exchange repair at
  the sender-intent level
- no relay test asserts that repair retries should suppress visible push alerts
- no smoke/integration test proves one recovery burst emits one repair action
  and zero visible contact-request alerts

## 8. Regression / Tests To Add First

Add these before or alongside the implementation:

1. sender-intent unit regression
   - file: `test/features/contact_request/application/send_contact_request_use_case_test.dart`
   - prove retry sends carry explicit non-user-facing intent while ordinary new
     requests keep current payload shape

2. overlap regression
   - file: `test/core/lifecycle/app_lifecycle_recovery_test.dart` or a new
     focused lifecycle test
   - prove `handleAppResumed()` plus the delayed `KeyExchangeRetrier` path
     collapse to one retry invocation in a single recovery burst

3. retrier-coordinator unit regression
   - file: `test/features/contact_request/application/key_exchange_retrier_test.dart`
   - prove the retrier does not fire if the shared retry coordinator already ran
     during the active resume/reconnect window

4. relay push regression
   - file: `go-relay-server/inbox_test.go`
   - prove repair-intent contact-request envelopes do not create visible push
     metadata while first-time request envelopes still do

5. fake-network integration regression
   - file: `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
   - prove one recovery burst results in one repair delivery and no second
     user-facing request materialization

6. smoke regression
   - file: either extend
     `test/features/contact_request/application/key_exchange_retry_smoke_test.dart`
     or add a new narrowly named smoke file
   - prove resume + reconnect + retry remains single-shot at the highest fake
     stack we have in-tree

## 9. Step-By-Step Implementation Plan

1. Introduce explicit send intent for contact requests.
   - Keep the default path as current user-facing `new_request`.
   - Add a retry-specific intent such as `key_exchange_retry`.
   - Only `retryIncompleteKeyExchanges()` should use the retry intent.

2. Add a shared retry coordinator for key-exchange repair.
   - One owner should serialize retry runs, track in-flight execution, and
     suppress immediate duplicate reruns from overlapping lifecycle triggers.
   - Wire the coordinator into both `handleAppResumed()` and
     `KeyExchangeRetrier`.

3. Stop direct double-entry into the raw retry use case.
   - `handleAppResumed()` should call the shared coordinator via an injected
     callback or service seam.
   - `KeyExchangeRetrier` should call the same coordinator after its debounce.
   - Preserve current fallback behavior for existing tests only where required.

4. Make repair retries non-user-facing at the relay push layer.
   - Teach relay push extraction to inspect the retry intent on the envelope.
   - For retry intent, skip visible contact-request push generation.
   - Keep first-time contact requests unchanged.

5. Keep receiver behavior stable.
   - Do not create a new contact-request row for existing contacts.
   - Do not change current `contactKeyUpdated` / `alreadyContact` semantics.

6. Add direct tests first, then fake-network integration, then smoke.
   - If the overlap regression proves the coordinator alone removes the
     duplicate and retry alerts are now silent, stop there.
   - Do not add broader protocol changes unless evidence still shows a user can
     receive duplicate visible pushes.

## 10. Risks And Edge Cases

- fully suppressing visible push for key-exchange repair may delay key
  convergence until the recipient next opens the app if no background delivery
  mechanism exists; if that becomes unacceptable, switch to background-only
  delivery rather than restoring a visible alert
- first-time contact requests must keep current push behavior and route payload
- accept-and-reciprocate flows must not regress; they also use
  `sendContactRequest()`
- resume ordering must stay intact; changing `handleAppResumed()` must not break
  existing health-check or inbox-drain sequencing
- relay-side suppression must not accidentally hide genuine first-time contact
  requests
- adding a long-lived stable `msgId` for retries is risky because the receiver
  replay cache treats repeated v2 `msgId` values as replays

## 11. Exact Tests And Gates To Run

Direct Flutter unit / integration:

- `flutter test test/features/contact_request/application/send_contact_request_use_case_test.dart`
- `flutter test test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
- `flutter test test/features/contact_request/application/key_exchange_retrier_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
- `flutter test test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `flutter test test/features/contact_request/integration/contact_request_flow_test.dart`
- `flutter test test/features/contact_request/application/key_exchange_retry_smoke_test.dart`

Relay direct suite:

- `cd go-relay-server && go test ./...`

Named / companion gates:

- `./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh completeness-check` if a new classified
  integration/smoke file is added or moved

Optional direct notification regression if payload shape changes:

- `flutter test test/integration/contact_request_notification_dedupe_integration_test.dart`

## 12. Known-Failure Interpretation

- treat any new failure in the direct contact-request, lifecycle, or relay
  suites above as a real regression for this session
- `scripts/run_test_gates.sh` is the gate source of truth
- `Test-Flight-Improv/test-gate-definitions.md` says the current named
  `transport` gate was revalidated green, but simulator/device selection still
  matters; if integration-backed transport runs fail to attach because of a
  device issue, rerun with explicit `FLUTTER_DEVICE_ID` before classifying the
  result as a code regression
- if a new integration or smoke file is added, update
  `Test-Flight-Improv/test-gate-definitions.md` so
  `./scripts/run_test_gates.sh completeness-check` stays green

## 13. Done Criteria

- exactly one repair retry path is observable per recovery burst
- repair retries no longer emit visible `"wants to connect"` pushes
- first-time contact-request push behavior is unchanged
- all new direct tests pass
- relay tests pass
- transport and 1:1 gates pass, or any unrelated infra/device-only failure is
  clearly isolated and documented

## 14. Scope Guard

Non-goals:

- no full contact-request protocol redesign
- no new persistent server-side notification history store
- no intro-feature changes
- no Orbit/Feed UX rework
- no broad push-framework rewrite

Overengineering for this session would include:

- introducing a new cross-feature reliability framework just for this bug
- inventing a long-lived global dedupe ID scheme across days
- widening frozen named gates instead of classifying one narrow new test if
  needed

## 15. Accepted Differences / Intentionally Out Of Scope

- repair retries may still use the existing `contact_request` transport
  envelope; the session only needs enough intent metadata to suppress the
  user-facing push path
- do not add deterministic cross-day message-ID reuse for repair retries;
  receiver replay-cache semantics make that risky without a separate protocol
- do not promote contact-request suites into a frozen named gate in this
  session; keep them as direct suites unless broader product policy changes

## 16. Dependency Impact

- future contact bootstrap work can reuse the send-intent seam added here
- future push-routing cleanup can reuse the relay retry-intent suppression logic
- if the coordinator design changes, revisit only the resume/reconnect retry
  callers, not the whole contact-request feature

# Structural Blockers Remaining

- none

# Incremental Details Intentionally Deferred

- whether repair retries should become true APNS/FCM background-only silent
  pushes instead of pure no-alert messages
- whether contact-request retry coverage deserves promotion into a frozen named
  gate after this bug is closed

# Accepted Differences Intentionally Left Unchanged

- first-time contact requests keep current visible push copy
- receiver-side existing-contact handling remains the same
- relay global dedupe behavior remains message-ID-based and pending-entry-based

# Exact Docs / Files Used As Evidence

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/contact_request/application/key_exchange_retrier.dart`
- `lib/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart`
- `lib/features/contact_request/application/send_contact_request_use_case.dart`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart`
- `lib/main.dart`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_store.go`
- `go-relay-server/backend_memory.go`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/features/contact_request/application/key_exchange_retrier_test.dart`
- `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
- `test/features/contact_request/application/key_exchange_retry_smoke_test.dart`
- `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/integration/contact_request_notification_dedupe_integration_test.dart`
- `go-relay-server/inbox_test.go`
- `go-relay-server/inbox_dedup_test.go`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

# Why The Plan Is Safe To Implement Now

The bug is localized and evidenced in both production logs and repo seams:

- the sender creates a fresh retry message every time
- two different client recovery paths can trigger that sender in the same burst
- the relay only suppresses exact duplicate pending message IDs
- the receiver already handles duplicate or existing-contact contact requests
  without creating user-visible local request UI

That makes the narrow plan above sufficient without reopening unrelated
messaging architecture.
