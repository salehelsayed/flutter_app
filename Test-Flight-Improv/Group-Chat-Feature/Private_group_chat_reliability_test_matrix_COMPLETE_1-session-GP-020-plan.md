# GP-020 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-020 | All expected connected returns to maintenance cadence | P1 | Covered | needs_tests_only |

## Gap Classification

GP-020 is repo-owned and runnable. The source row remained `Open` even
though the discovery cadence policy already returned to maintenance cadence
when all expected group members were connected. The missing piece was an exact
row-owned regression proving that all-connected and zero-expected-member states
reset backoff/failure state and replenish the warm retry budget.

## Implementation Plan

1. Add an exact GP-020 Go regression in `go-mknoon/node/pubsub_test.go`.
2. Seed an already-backed-off cadence state with no warm retries remaining.
3. Simulate a transition where `afterConnected == expectedConnected`.
4. Prove the next interval is `GroupDiscoveryInterval`, backing off is false,
   consecutive failures reset to zero, and warm retries are replenished.
5. Prove the zero-expected-member path also returns to maintenance cadence and
   resets warm retry state.
6. Run focused, adjacent, broader, selected race, named groups, and diff
   hygiene gates.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGP020AllExpectedConnectedReturnsToMaintenanceCadence`.
- `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP020AllExpectedConnectedReturnsToMaintenanceCadence' -count=1` passed (`ok node 0.616s`).
- `cd go-mknoon && go test ./node -run 'TestGP020|TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 11.056s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP020|TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 12.188s`, `ok internal 0.300s`, `ok crypto 0.899s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP020|TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 12.271s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-020 is now `Covered` by exact row-owned native proof. No
production runtime change was required for GP-020: all expected connected
members and zero expected members already return discovery to maintenance
cadence, clear failure/backoff state, and replenish warm retries. Residual-only:
none for GP-020. Continue from GI-034, the next unresolved row in ordered
ledger order.
