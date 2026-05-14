# GP-018 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-018 | Warm retry cadence keeps active group responsive | P1 | Covered | needs_tests_only |

## Gap Classification

GP-018 is repo-owned and runnable. The source row remained `Open` even though
the discovery loop already had warm retry behavior for partially connected
groups. The exact row-owned proof was missing, and the cadence decision lived
inside the long-running loop, which made deterministic interval assertions
awkward.

The implementation extracted the cadence decision into narrow helpers without
changing the runtime policy, then added an exact GP-018 regression proving the
warm retry window stays responsive before exponential backoff begins.

## Implementation Plan

1. Extract the discovery cadence decision from `groupPeerDiscoveryLoop` into
   small testable helpers.
2. Add an exact GP-018 Go regression in `go-mknoon/node/pubsub_test.go`.
3. Prove a partially connected group starts at `GroupDiscoveryWarmInterval`.
4. Prove bounded no-progress retries stay at the warm interval with no
   avoidable `GroupDiscoveryInterval` gap.
5. Prove the first post-warm no-progress cycle backs off from the warm interval
   rather than jumping to the 30 second maintenance interval.
6. Run focused, adjacent, broader, selected race, named groups, and diff
   hygiene gates.

## Execution Evidence

- Extracted `go-mknoon/node/pubsub.go::initialGroupDiscoveryCadence` and
  `go-mknoon/node/pubsub.go::nextGroupDiscoveryCadence`.
- Added `go-mknoon/node/pubsub_test.go::TestGP018WarmRetryCadenceKeepsActiveGroupResponsive`.
- `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP018WarmRetryCadenceKeepsActiveGroupResponsive' -count=1` passed (`ok node 0.493s`).
- `cd go-mknoon && go test ./node -run 'TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 11.407s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 13.306s`, `ok internal 1.570s`, `ok crypto 1.038s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 14.474s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-018 is now `Covered` by exact row-owned native proof. The
row required a narrow helper extraction for deterministic coverage, but no
runtime cadence policy changed: active partial groups stay on warm retries for
the bounded retry window, then back off from the warm interval without an
avoidable 30 second foreground catch-up gap. Residual-only: none for GP-018.
Continue from GI-034, the next unresolved row in ordered ledger order.
