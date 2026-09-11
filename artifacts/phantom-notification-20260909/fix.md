# Direct iPhone notification replay fix

The code defect is reproduced: an acknowledged direct message can be stored
again for delivery recovery, receiving a new relay custody ID. Previously that
new custody row also generated a new iPhone push for the old ciphertext.

Sender retries are intentional. A delivered message can still have independent
immutable relay custody waiting for exact completion. Changing sender settlement
or refusing the relay re-store would break that delivery contract. The iOS
extension can present the old trusted preview while the app correctly treats the
message as a duplicate, producing the reported notification with no new message.
This mechanism is proven in deterministic tests; the historical incident still
lacks the message-to-push identifier needed to reconstruct its exact route.

## Change

- Add a separate iOS provider-dispatch claim, independent of inbox storage and
  ACK. Redis retains it across relay restarts for seven days, matching the
  existing notification recovery horizon. The memory backend covers local mode.
- Scope the claim to the authenticated sender, recipient, and namespaced message
  event. Without an explicit edit event ID, include a digest of canonical
  ciphertext/payload so an exact immutable replay is suppressed and a legacy edit
  with changed ciphertext remains a distinct notification. JSON key ordering does
  not change the identity. No message content or identifiers are added to logs.
- Claim at the resolved iOS provider boundary, covering normal pushes and stale
  route re-selection. Pass the same hashed identity through fixed-mailbox capacity
  fallback and persisted delayed wakes, including rich-to-opaque route changes.
- Retain successful claims; release claims after explicit unsuccessful provider
  results, using a bounded cleanup context that survives send cancellation.
  Deduplication backend failure preserves notification delivery rather than adding
  a new silent-message failure. Existing group admission and Android recovery
  behavior are preserved.

Primary source:

- `go-relay-server/direct_message_dispatch_admission.go`: direct identity/backend.
- `go-relay-server/group_message_dispatch_admission.go`: shared expiring,
  owner-checked claim mechanics; existing group keys remain compatible.
- `go-relay-server/inbox.go`: provider admission and direct wake propagation.
- `go-relay-server/wake_outcome.go`: durable direct dispatch identity/coordinator.
- `go-relay-server/server_bootstrap.go`: production Redis and coordinator wiring.

## Regression evidence

`direct_notification_replay_test.go` failed before the fix in five cases:
memory legacy, Redis legacy, Redis protected custody, and both Redis lanes with
recreated services. The same ciphertext was accepted for recovery but incorrectly
produced two provider sends. Those cases pass after the fix with one send.

Additional tests preserve sender/recipient isolation, distinct message/edit events,
legacy edits, equivalent JSON serialization, failed-provider retry, concurrent
attempts, Android behavior, seven-day expiry, and delivery during admission-store
failure.

`direct_notification_wake_replay_test.go` separately failed for capacity fallback
and rich-to-delayed route transition. Both now pass. Its existing completed-wake
case passes before and after the change. Asynchronous tests wait for observed
suppression rather than treating a short period without output as success.

Evidence files are `direct-notification-replay-red.txt`,
`direct-notification-replay-green.txt`, and
`direct-notification-wake-red-green.txt`.

## Operational scope

This patch is local and has not been deployed. It requires a relay deployment;
no iPhone app release is required. Its event memory begins with claims recorded
by the updated relay and cannot cancel pushes already accepted by the provider.
Suppression is bounded to seven days and requires the claim backend to be
available. A process interruption around the provider call can leave an
ambiguous claim until expiry; it does not remove message custody or delivery.

A subsequent sender audit found separate early-receipt and permanently rejected
task issues. Those are now fixed in a separate local app patch documented in
`sender-fixes.md`; applying those sender fixes requires an app update.

## Validation

All final validation uses `GOTOOLCHAIN=go1.25.0`, the relay Makefile's pinned
toolchain. An initial run on the system Go 1.27 toolchain hit the known QUIC/TLS
session-ticket panic; its log is retained as `relay-full-test.log`.

- Focused direct-notification race tests pass on Go 1.25.0:
  `go test -race ./... -run '^TestDirectNotification' -count=1 -timeout=5m`
  (2.472 seconds; `direct-notification-race-test-go125.log`).
- The first full Go 1.25.0 run reached completion without the QUIC/TLS panic,
  but exposed two source-architecture assertions that expected the previous
  direct sender gateway (`relay-full-test-go125-initial.log`). Updated assertions
  verify the admission-aware direct paths and preserve the private resolver and
  shared provider/retry boundary. Both focused architecture tests pass
  (26.022 seconds; `gateway-architecture-test-go125.log`).
- Full relay suite passes on Go 1.25.0:
  `go test ./... -count=1 -timeout=10m`
  (85.559 seconds; `relay-full-test-go125.log`).
- `git diff --check -- go-relay-server` passes. Changed-file impact analysis and
  incremental architecture graph refresh have completed for all nine changed
  relay source/test files. Formatting checks are clean.
