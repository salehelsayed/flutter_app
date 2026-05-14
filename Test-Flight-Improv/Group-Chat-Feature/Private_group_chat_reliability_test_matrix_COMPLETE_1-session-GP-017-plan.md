# GP-017 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-017 | In-flight dial gate blocks duplicate dials only while active | P1 | Covered | needs_code_and_tests |

## Gap Classification

GP-017 is repo-owned and runnable. The source row remained `Open` even though
the current dial-gate state machine already tracks active dials separately from
cooldown state in `beginGroupPeerDialWithMode` and `finishGroupPeerDial`. The
row needed exact proof that an in-flight duplicate is blocked only while active,
and that the next cycle can proceed after success or follow normal cooldown
after failure.

## Implementation Plan

1. Add an exact GP-017 Go regression in `go-mknoon/node/pubsub_test.go`.
2. Prove a second discovery cycle for the same peer is blocked while the first
   dial is active, with `retryIn == 0` and `blockedByInFlight == true`.
3. Prove a successful first dial clears the in-flight gate so a third discovery
   cycle is allowed immediately after finish.
4. Prove a failed first dial clears the in-flight gate but leaves the normal
   cooldown policy active, and that retry is allowed after the cooldown expires.
5. Run focused, adjacent, broader, selected race, named groups, and diff
   hygiene gates.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGP017InFlightDialGateBlocksOnlyWhileActive`.
- `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP017InFlightDialGateBlocksOnlyWhileActive' -count=1` passed (`ok node 0.499s`).
- `cd go-mknoon && go test ./node -run 'TestGP017|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestGroupDiscoveryDialBackoffAllowsRetryAfterCooldown|beginGroupPeerDialWithMode|GroupDiscoveryBackoff' -count=1` passed (`ok node 0.359s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP017|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestGroupDiscoveryDialBackoffAllowsRetryAfterCooldown|beginGroupPeerDialWithMode|GroupDiscoveryBackoff' -count=1` passed (`ok node 0.390s`, `ok internal 0.623s`, `ok crypto 0.939s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP017|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestGroupDiscoveryDialBackoffAllowsRetryAfterCooldown|GroupDiscoveryBackoff' -count=1` passed (`ok node 1.688s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-017 is now `Covered` by exact row-owned native proof. No
production code change was required because current in-flight tracking already
separates active duplicate-dial blocking from post-failure cooldown policy.
Residual-only: none for GP-017. Continue from GI-034, the next unresolved row
in ordered ledger order.
