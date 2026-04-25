# 73 - Session 1 Plan: Relay Ciphertext-Only Push Contract

## Scope

Implement the server-owned Phase 1 slice from
`Test-Flight-Improv/73-on-device-push-decrypt-plan.md`:

- message pushes for 1:1, group, and dissolve-style group replay envelopes stop
  emitting plaintext preview fields
- APNs message pushes carry `mutable-content` and a static fallback alert
- Android message pushes are data-only
- relay data payloads include only routing metadata and encrypted envelope
  material needed by later device-side decrypt handlers
- contact-request, introduction, and group-invite push behavior stays out of
  this session except for regressions that prove it was not accidentally
  changed
- relay tests prove group fanout still excludes the sender and dedupes
  recipients

## Code Entry Points

- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `go-relay-server/metrics.go` only if the focused implementation needs a
  small aggregate rollout metric

## Tests And Gates

Focused verification:

- `go test ./go-relay-server/...`

Targeted test coverage:

- 1:1 chat push data contains route metadata and encrypted fields but no
  `sender_username`, `senderUsername`, `title`, or plaintext `body`
- 1:1 APNs payload has static fallback body and `mutable-content`
- 1:1 Android payload is data-only
- group push data contains group route metadata and encrypted fields but no
  `title` or plaintext `body`
- group APNs payload has static fallback body and `mutable-content`
- group Android payload is data-only
- group fanout keeps durable-store-before-push behavior, excludes sender, and
  dedupes recipients

Named gates:

- No Flutter named gate is required for this isolated Go relay session unless
  Dart, iOS, or stable gate docs are changed during execution.

## Done Criteria

- The relay no longer emits message preview plaintext in APNs, FCM data, or
  Android notification fields for 1:1/group message pushes.
- Non-message push tests remain green.
- `go test ./go-relay-server/...` passes or any failure is recorded as a real
  blocker with evidence.
- The session ledger in
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md` is
  updated with the execution outcome.

## Scope Guard

- Do not implement client send-path redaction, Android decrypt handling, iOS
  NSE work, fixture generation, telemetry gates, or cleanup in this session.
