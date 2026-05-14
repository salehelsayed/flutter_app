# GP-024 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-024 | Subscription error exits only on real subscription failure | P1 | Covered | needs_tests_only |

## Gap Classification

GP-024 is repo-owned and runnable. The source row remained `Open` because the
subscription loop handled a canceled context quietly only when `ctx.Err()` was
already set, and no exact row-owned regression pinned direct `context.Canceled`
or `context.DeadlineExceeded` subscription errors versus real stream failures.
The row needed a narrow production helper plus exact native proof.

## Implementation Plan

1. Add a small classifier used by `handleGroupSubscription`.
2. Treat canceled subscription contexts, `context.Canceled`, and
   `context.DeadlineExceeded` as quiet shutdown paths.
3. Keep non-context subscription failures loggable before the handler returns.
4. Add an exact GP-024 Go regression in `go-mknoon/node/pubsub_test.go`.
5. Run focused, adjacent subscription-handler, broader Go, selected race, named
   groups, and diff hygiene gates.

## Execution Evidence

- Added `go-mknoon/node/pubsub.go::shouldLogGroupSubscriptionError` and wired it
  into `handleGroupSubscription`.
- Added `go-mknoon/node/pubsub_test.go::TestGP024SubscriptionErrorLogsOnlyRealFailures`.
- `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP024SubscriptionErrorLogsOnlyRealFailures' -count=1` passed (`ok node 0.538s`).
- `cd go-mknoon && go test ./node -run 'TestGP024|TestHandleGroupSubscription|TestGL013HandleGroupSubscription|TestGK016HandleGroupSubscription|TestGK018HandleGroupSubscription|TestGK019HandleGroupSubscription|TestGK020HandleGroupSubscription|TestGK021HandleGroupSubscription' -count=1` passed (`ok node 17.200s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP024|TestHandleGroupSubscription|TestGL013HandleGroupSubscription|TestGK016HandleGroupSubscription|TestGK018HandleGroupSubscription|TestGK019HandleGroupSubscription|TestGK020HandleGroupSubscription|TestGK021HandleGroupSubscription' -count=1` passed (`ok node 17.484s`, `ok internal 0.340s`, `ok crypto 0.926s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP024|TestHandleGroupSubscription|TestGL013HandleGroupSubscription|TestGK016HandleGroupSubscription|TestGK018HandleGroupSubscription|TestGK019HandleGroupSubscription|TestGK020HandleGroupSubscription|TestGK021HandleGroupSubscription' -count=1` passed (`ok node 18.948s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-024 is now `Covered` by exact row-owned native proof plus a
narrow classifier in the subscription loop. Context cancellation and deadline
termination now exit quietly whether surfaced through the loop context or as the
returned subscription error, while real non-context subscription failures remain
loggable before return. Residual-only: none for GP-024. Continue from GI-034,
the next unresolved row in ordered ledger order.
