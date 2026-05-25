# PubSub Forwarded Origin Validator Session Breakdown

Source request date: 2026-05-23

Source proposal/matrix/closure doc: this self-contained breakdown, created for
the confirmed Go PubSub validator bug where valid forwarded GossipSub group
messages can be rejected as `peer_mismatch` or `unbound_device`.

Recommended plan count: 1

## Run Mode Snapshot

- Active mode: standard
- Degraded local continuation explicitly allowed: no
- Source proposal, matrix, or closure doc path:
  `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md`
- Source row/status vocabulary: session ledger statuses only
- Overall closure bar: a valid signed group envelope whose sender transport
  matches the signed PubSub author is accepted even when the validator receives
  it from a different forwarding peer; forged author/envelope mismatches remain
  rejected.
- Final verdict policy: `closed` only after the session is accepted with direct
  Go regression evidence and a persisted final program verdict.

## Session Ledger

| Session ID | Title | Classification | Plan File | Dependencies | Status | Execution Verdict | Closure Docs | Blocker Class | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `GPF-001` | Forwarded GossipSub validator uses signed PubSub author, not forwarding peer | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md` | None | `accepted` | Accepted: RED reproduced forwarded accept failures; post-fix combined targeted command passed with `ok github.com/mknoon/go-mknoon/node 0.469s`; `git diff --check` passed; full `go test ./node` red only on clean-HEAD-reproduced unrelated failures. | Updated: `Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md`; this breakdown. | None | Docs touched for closure only; remaining full-node failures `GI012`-`GI016`, `GA019`, `GA021`, and `GM028` are residual-only/pre-existing. |

## Ordered Session Breakdown

### GPF-001: Forwarded GossipSub Validator Uses Signed PubSub Author

Classification: `accepted`

Exact scope:

- Production: `go-mknoon/node/pubsub.go`
- Tests: `go-mknoon/node/pubsub_test.go`
- Behavior: validator transport/device binding must use the signed PubSub
  author (`msg.GetFrom()`) instead of the validator `pid`, which can be only
  the forwarding peer.

Completed direct regressions:

- Added a validator test where `env.SenderTransportPeerId` and `msg.From` are
  Alice, validator `pid` is Carol, and the message is accepted.
- Preserved a rejection test where `msg.From` does not match
  `env.SenderTransportPeerId`.
- Covered device-bound member flow so `activeMemberDeviceForEnvelope` is called
  with the origin transport id, not the forwarding peer id.

Executed commands:

- `cd go-mknoon && go test ./node -count=1 -run 'TestSV004ForgedSenderIdentityOrSignatureRejectsWithSafeDiagnostics|TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages|TestGroupTopicValidator_TransportPeerIdMatchesEnvelopeSender|TestGroupTopicValidator_RejectsTransportPeerIdMismatch|TestGroupTopicValidator_DeviceBoundMemberAcceptsRegisteredDevice|TestGroupTopicValidator_DeviceRejectsUnboundSibling'` passed locally with `ok github.com/mknoon/go-mknoon/node 0.469s`.
- `git diff --check -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-GPF-001-plan.md Test-Flight-Improv/Group-Chat-Feature/pubsub-forwarded-origin-validator-session-breakdown.md` passed locally.
- `cd go-mknoon && go test ./node` remains red only on pre-existing unrelated failures reproduced at clean detached HEAD: `GI012`-`GI016`, `GA019`, `GA021`, and `GM028`.

Named gates: none; this is Go-node-only validator behavior.

Dependency state: no dependencies.

Matrix or closure docs updated:

- This breakdown ledger and final program verdict.
- The session plan's execution and closure sections.

Structural blockers: none.

Acceptance notes:

- Production changed only `go-mknoon/node/pubsub.go`: `Node.groupTopicValidator`
  now binds transport/device checks to `originTransportPeerId`, derived from
  `msg.GetFrom().String()`, with a fallback to `pid.String()` only when the
  PubSub author is empty.
- Tests changed only `go-mknoon/node/pubsub_test.go`: added
  `TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages`.
- The empty-author fallback is accepted as a small compatibility difference
  that preserves legacy no-author direct validation behavior without weakening
  the non-empty forwarded-author runtime path.

## Downstream Execution Path

For `GPF-001`, completed:

1. Ensured the doc-scoped plan exists and is execution-safe.
2. Executed with `$implementation-execution-qa-orchestrator`.
3. Closed with `$implementation-closure-audit-orchestrator`.
4. Ran final program acceptance and persisted one final verdict here.

## Controller Progress

- 2026-05-23 | Controller initialized | Created one-session breakdown for the confirmed Go PubSub forwarded-origin validator bug | Next action: spawn planning agent for `GPF-001`.
- 2026-05-23 | GPF-001 accepted | RED evidence reproduced the forwarded-origin bug; post-fix targeted regression command and `git diff --check` passed | Next action: no GPF-001 implementation work remains.
- 2026-05-23 | Final program closure | Full `go test ./node` remains red only on `GI012`-`GI016`, `GA019`, `GA021`, and `GM028`, which reproduced at clean detached HEAD | Next action: treat those failures as residual-only/pre-existing for this program verdict.

## Final Program Verdict

closed

Final acceptance note: `GPF-001` is closed. Reopen only on a real regression in
forwarded PubSub author binding, forged author/envelope rejection, or
device-bound forwarded author validation. The current full-node red state is
residual-only because the remaining failures reproduced without this session's
changes.
