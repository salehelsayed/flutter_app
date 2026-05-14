# GP-013 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-013 | Direct address preference excludes relay circuit addrs | P1 | Covered | needs_tests_only |

## Gap Classification

GP-013 is repo-owned and runnable. The current production path already keeps
relay circuit addresses out of direct dialing through `collectDirectMultiaddrs`
and uses relay only as a distinct fallback path in
`connectGroupPeerPreferDirect`, but the source row remained `Open` without
exact row-owned proof.

## Implementation Plan

1. Add an exact GP-013 Go regression in `go-mknoon/node/pubsub_test.go`.
2. Build a peerstore/candidate-address set containing a real target direct
   address plus a synthetic `/p2p-circuit` relay address for the same peer.
3. Verify `collectDirectMultiaddrs` returns only non-circuit addresses and
   dedupes mixed peerstore/candidate input.
4. Verify `connectGroupPeerPreferDirect` records a direct attempt, uses only
   the direct address count, succeeds over the direct path, and does not mark
   relay fallback used.
5. Run focused, adjacent, broader, selected race, named groups, and diff
   hygiene gates.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs`.
- `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP013DirectAddressPreferenceExcludesRelayCircuitAddrs' -count=1` passed (`ok node 0.572s`).
- `cd go-mknoon && go test ./node -run 'TestGP013|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay|connectGroupPeerPreferDirect|collectDirectMultiaddrs|relay_fallback' -count=1` passed (`ok node 0.418s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP013|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay|connectGroupPeerPreferDirect|collectDirectMultiaddrs|relay_fallback' -count=1` passed (`ok node 0.435s`, `ok internal 0.894s`, `ok crypto 0.649s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP013|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay' -count=1` passed (`ok node 1.792s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-013 is now `Covered` by exact row-owned native proof. No
production code change was required because current direct-address collection
already filters `/p2p-circuit` addresses and keeps relay fallback separate.
Residual-only: none for GP-013. Continue from GI-034, the next unresolved row
in ordered ledger order.
