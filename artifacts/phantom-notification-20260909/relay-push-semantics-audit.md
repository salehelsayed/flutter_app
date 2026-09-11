# Relay push semantics audit

Incident window: 2026-09-09 about 21:30 Europe/Berlin (19:30 UTC).

## Live relay observations

- Active executable: `/usr/local/bin/relay-server`, PID `1069706`; process started `2026-09-09 00:44:01 UTC`.
- Active executable SHA-256: `c7df62af73ad3067137d10d0239085aaa1187e8dae71b905161f98e8bdfd9501`.
- Embedded build metadata: Go `1.25.0`, Linux amd64, `vcs.revision=d8b919c5b34575d570a78eb5fbbc4203f56f875b`, `vcs.time=2026-09-07T20:06:44Z`, `vcs.modified=true`.
- The executable differs from both inspected local artifacts: `build/app-diagnostics/deploy-bundle/relay-server` (`17788bd497a138a0625c6fa76a2c9377a82503eda01c4826241e1c287f81639c`) and `go-relay-server/relay-server` (`8e761700b7ea2b52e8a994c0f9d66f5d4d0db4056993ca15e8b54149e76e135e`). Current-source behavior below is therefore supporting interpretation, not an exact deployed-source attestation.
- A direct journal query covering 18:30–19:32 UTC confirms three `[PUSH] outcome=success attempt=1 total_attempts=3` entries at 19:03:08, then the next at 19:31:07. These entries contain no recipient or message identifier, so the three earlier successes cannot individually be attributed to the friend.
- The same journal window shows no service restart entries. A global journal scan in the same window found no message suppression, journal restart/rotation, or rate-limit records.
- `systemctl show relay-server`: `StandardOutput=journal`, `StandardError=inherit`, `LogRateLimitIntervalUSec=0`, `LogRateLimitBurst=0`.

## Current-source interpretation

- `go-relay-server/inbox.go:1086` is the provider send wrapper. Targeted search of the relay Go source found its only real Firebase client call at line 1093 and its callers inside `sendWithRetry` at lines 1117 and 1162. Accepted ordinary attempts immediately increment the success counter and emit `[PUSH] outcome=success` at lines 1125–1128; the strict payload-size rescue does likewise at lines 1170–1174. There is no sampled or rate-limited application logger on this path.
- Default relay retry delays are 250 milliseconds and 1 second (`inbox.go:74`). Transient retry, exhausted retry, and cancellation dispositions are logged at lines 1196, 1201 and 1205. Firebase has its own lower-level retry behavior, explicitly distinguished from relay-attempt counts by `push_permanent_error_closure_test.go:175`.
- iOS is excluded from the independent Android ciphertext retry queue (`android_rich_push_recovery.go:91`, `:212`). The ordinary durable wake admission requires opaque wake capability (`wake_outcome.go:192`), so that mechanism is not evidence of a late iOS rich-preview replay.
- `[INBOX] Stored message` logs a newly stored transport row (`inbox.go:2783`), including rows which do not qualify for notifications. `ShouldNotify` and wake authorization are applied afterward (`inbox.go:2794`, `:2938`). The metadata switch accepts ordinary chat and certain other visible event types, suppresses key-exchange retry contact requests, and defaults unsupported traffic to no notification (`inbox.go:2025`). The logged timestamp is receipt/store time, not proof of a new human-authored message.
- Ordinary store sender attribution is the authenticated libp2p remote peer, not a caller-provided `from` field (`inbox.go:4321`). This authenticates the client identity, not whether the user tapped Send at that moment.
- An ordinary duplicate store returns before launching a push (`inbox.go:2592`). This does not alone rule out client replay using a different identity or a new store after retention expires.
- Ordinary chat push content is encrypted metadata plus a generic APNS alert (`inbox.go:1234`, `:1434`); the relay does not obtain the cleartext phrase from this path.

## Bounded conclusion

There is no recorded provider-accepted relay push between 19:03:08 and 19:31:07 UTC in the inspected live journal, with no observed restart or log-suppression indication. This weakens a newly submitted relay notification around 19:28–19:30 as the explanation. It does not establish when the recipient device displayed a previously accepted push, exclude an SDK/provider acknowledgement ambiguity, identify the earlier recipient, or explain a missing conversation row. The inbox store lines alone do not prove a newly sent user message.

## Focused validation

Passed on current local source:

```text
go test ./... -run '^(TestInboxStore_UnsupportedEnvelopeDoesNotSendPush|TestInboxStore_KeyExchangeRetryContactRequestDoesNotSendPush|TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken|TestRelayNotificationClosure_DirectDuplicateDoesNotRefanoutPush)$' -count=1
ok github.com/mknoon/relay-server 27.405s
```

The first two tests prove stored control/unsupported envelopes can produce no push. The transient test preserves three relay attempts and token custody. The direct duplicate test uses an iOS route and proves the second identical store does not refanout a push.

Graph navigation context: initial parent packet `9ea0a5f217484f1f` / `47ef1e2cf8a06cca`; focused inbox refinement `ca5f3d9f43c34c5e` / `4e70eabfdec5ecd7`. No production source was changed and no remote mutation, notification send, or service action was performed.
