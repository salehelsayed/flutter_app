# Predeployment notification history gap

The focused overlay regression reproduces an old notification immediately after
a genuinely new one even with the current durable iOS replay guard enabled.

## Observed result

`TestDirectNotificationPredeploymentHistoryGap` was run with Go 1.25.0. The
`predeployment_history_missing` case fails the desired behavior assertion:

```
provider sequence=[old-authored-before-deployment genuinely-new-message old-authored-before-deployment]
want=[old-authored-before-deployment genuinely-new-message]
```

The paired `control_historical_admission_retained` case passes, yielding exactly
`[old-authored-before-deployment genuinely-new-message]`. Both cases also verify
that one further identical old replay is suppressed after the guard has a claim.
The complete command exits 1 because the first case intentionally asserts the
desired behavior and exposes the defect. See `predeployment_repro_output.txt`.

## Mechanism isolated by the test

1. Redis custody accepts the old message, and the provider accepts its iOS alert.
2. Inbox ACK removes its custody row.
3. A fresh PushService starts with the current Redis admission backend and the
   same Redis data.
4. A genuinely new message is stored and notified successfully.
5. The old immutable ciphertext is stored again under a new custody ID.

For the historical send, the failing case invokes
`sendSelectedPushThroughGateway` without an admission identity. This is the
exact final adapter used by committed HEAD's pre-patch `sendRichNotification`;
it models delivery before the guard existed, with a healthy Redis service. The
control instead uses the current `sendStoredNotification` adapter for that first
send, creating the durable admission claim before the simulated restart.

The failing case's new send and first old replay both log
`DIRECT_MESSAGE_DISPATCH_ADMISSION outcome=acquired` followed by provider success.
An admission system with no historical record has no way to identify that old
message's previously accepted alert on its first post-deployment replay. That
replay seeds the missing record, so a subsequent repeat is suppressed.

Custody and notification calls are driven synchronously to isolate history
retention from goroutine scheduling. The fixture uses the real Redis inbox
Store/ACK implementation, Redis admission backend, provider gateway, and
recording provider. It does not model a sender's replay scheduling or decrypt
real incident messages.

## Reproduction command

Run from `/Volumes/CrucialX9/flutter_app/go-relay-server`:

```sh
GOTOOLCHAIN=go1.25.0 go test \
  -overlay=/Volumes/CrucialX9/flutter_app/artifacts/phantom-notification-20260910/predeployment_overlay.json \
  -run '^TestDirectNotificationPredeploymentHistoryGap$' -count=1 -v .
```

The overlay adds only a virtual Go test file. Production code and the repository's
test files were not changed. Source/test navigation used Graphify query
`6ca57a1d39204e60`, evidence digest `36df27c1e684f1ab`, refining the existing
incident branch around the exact provider admission identity and replay test.
