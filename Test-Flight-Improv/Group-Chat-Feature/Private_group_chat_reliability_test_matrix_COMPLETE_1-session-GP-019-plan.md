# GP-019 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-019 | Discovery backoff resets after partial progress | P1 | Covered | needs_tests_only |

## Gap Classification

GP-019 is repo-owned and runnable. The source row remained `Open` even though
the discovery cadence policy already reset failures when the connected-member
count improved but still remained below the expected member count. The missing
piece was an exact row-owned regression proving that partial progress exits
backoff, returns to warm cadence, and refreshes the warm retry budget.

## Implementation Plan

1. Add an exact GP-019 Go regression in `go-mknoon/node/pubsub_test.go`.
2. Seed an in-backoff state with missing expected members.
3. Advance from a lower connected count to a higher count that is still below
   the expected count.
4. Prove the next interval is `GroupDiscoveryWarmInterval`, backing off is
   false, consecutive failures reset to zero, and warm retries are replenished.
5. Prove the next no-progress cycle consumes the refreshed warm retry budget
   instead of immediately backing off again.
6. Run focused, adjacent, broader, selected race, named groups, and diff
   hygiene gates.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGP019DiscoveryBackoffResetsAfterPartialProgress`.
- `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP019DiscoveryBackoffResetsAfterPartialProgress' -count=1` passed (`ok node 0.663s`).
- `cd go-mknoon && go test ./node -run 'TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 13.378s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 13.525s`, `ok internal 1.114s`, `ok crypto 0.548s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP019|TestGP018|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|GroupDiscoveryWarm|GroupDiscoveryBackoff' -count=1` passed (`ok node 12.665s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-019 is now `Covered` by exact row-owned native proof. No
additional production runtime change was required for GP-019: partial progress
while expected members are still missing resets failure/backoff state, returns
to warm cadence, and refreshes the warm retry budget. Residual-only: none for
GP-019. Continue from GI-034, the next unresolved row in ordered ledger order.
