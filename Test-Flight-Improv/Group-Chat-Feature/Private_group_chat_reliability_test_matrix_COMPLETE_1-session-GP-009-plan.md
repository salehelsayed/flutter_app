# GP-009 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-009 | Discovery loop registers and discovers after relay readiness | P1 | Open | needs_tests_only |

## Gap Classification

GP-009 is repo-owned and runnable. The relevant native behavior lives in
`go-mknoon/node/pubsub.go::groupPeerDiscoveryLoop`: the loop performs a
pre-relay direct recovery attempt, then waits for `relayReady`, then performs
relay-assisted known-member dialing and rendezvous register/discover cycles.

Existing adjacent GR-014 evidence proves late relay readiness resumes discovery,
but the row-owned matrix entry is still `Open` and lacks exact GP-009 evidence
that compares pre-relay behavior with post-relay register/discover behavior.

## Implementation Plan

1. Add an exact GP-009 live-node Go regression in
   `go-mknoon/node/pubsub_delivery_test.go`.
2. In the test, join a group while node A's `relayReady` channel is still open.
3. Prove node A emits `pre_relay_direct_dial` before relay readiness and does
   not call relay dial, rendezvous register, or rendezvous discover before the
   channel closes.
4. Close `relayReady`, then prove relay-assisted known-member dialing,
   rendezvous registration, and rendezvous discovery occur afterward.
5. Run focused, adjacent, selected race, named groups, and diff hygiene gates.

## Acceptance Bar

- GP-009 source matrix row is `Covered`.
- The exact test proves both sides of the timing contract with concrete event
  and hook evidence.
- No production behavior changes are needed unless the exact test exposes a
  repo-owned implementation gap.

## Execution Evidence

Implemented exact row-owned coverage in
`go-mknoon/node/pubsub_delivery_test.go::TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady`.
The test joins a private group while node A's `relayReady` channel is still
open, observes `pre_relay_direct_dial` before readiness, verifies relay dial,
rendezvous register, and rendezvous discover hooks remain at zero before
readiness, closes `relayReady`, then proves known-member relay dial success,
`registered`, `discover_result`, and hook order `register:<group namespace>`
before a later `discover:<group namespace>`.

Validation passed:

- `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
- `cd go-mknoon && go test ./node -run 'TestGP009GroupDiscoveryRegistersAndDiscoversAfterRelayReady' -count=1` (`ok node 2.901s`)
- `cd go-mknoon && go test ./node -run 'TestGP009|TestGR014|GroupPeerDiscoveryLoop|GroupDiscoveryCycle|KnownGroupMemberDial' -count=1` (`ok node 16.204s`)
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP009|TestGR014|GroupPeerDiscoveryLoop|GroupDiscoveryCycle|KnownGroupMemberDial' -count=1` (`ok node 13.876s`, `ok internal 0.937s`, `ok crypto 0.683s`)
- `cd go-mknoon && go test -race ./node -run 'TestGP009|TestGR014|GroupPeerDiscoveryLoop|KnownGroupMemberDial' -count=1` (`ok node 14.430s`)
- `./scripts/run_test_gates.sh groups` (`+160`)

## Final Verdict

Accepted/closed. GP-009 is `Covered` with exact native relay-readiness
discovery evidence. No production runtime change was required because the
current discovery loop already performed pre-relay direct recovery before
waiting on `relayReady`, then ran relay-assisted known-member dial and
rendezvous register/discover after readiness once exact proof was added.

Residual-only: none for GP-009. Continue from GI-034, the next unresolved
session in ordered ledger order; do not write a final program verdict while
later rows remain unresolved.
