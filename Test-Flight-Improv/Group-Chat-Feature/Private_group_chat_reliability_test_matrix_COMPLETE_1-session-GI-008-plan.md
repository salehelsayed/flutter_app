# GI-008 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GI-008 | GroupInboxStore resets failed stream and closes successful stream | P1 | Covered | needs_tests_only |

## Gap Classification

GI-008 was repo-owned and runnable. The source row remained `Open` because no
exact row-owned proof observed the stream cleanup behavior for a failed
`GroupInboxStore` relay attempt followed by a successful relay attempt.
Production inspection found `GroupInboxStore` already defers `finishStream` with
`streamOK == false` until the relay returns `OK`, and `finishStream` resets
failed streams while cleanly closing successful streams. The row could close
with an exact native regression rather than runtime code.

## Implementation Plan

1. Add a GI-008 Go regression beside the existing GroupInboxStore relay retry
   tests.
2. Force the first relay to return non-OK and then observe the client-side stream
   termination from the relay handler.
3. Force the second relay to return OK and observe clean client-side closure.
4. Assert relay attempt order, failed-stream reset behavior, and successful
   stream close behavior.
5. Run exact, adjacent, broader, race, relay-server, Flutter app-side inbox, and
   named groups gate evidence.

## Execution Evidence

- Added `go-mknoon/node/group_inbox_test.go::TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream`.
- Existing production path inspected: `go-mknoon/node/group_inbox.go::GroupInboxStore` and `go-mknoon/node/node.go::finishStream`.
- `gofmt -w go-mknoon/node/group_inbox_test.go` passed.
- `go test ./node -run '^TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream$' -count=1` passed (`ok node 0.588s`).
- `go test ./node -run 'Test(BuildGroupInboxStoreRequest|GM028BuildGroupInboxStoreRequest|GI00(1|2|3|5|6|7|8)GroupInboxStore|GI035GroupInboxStore)' -count=1` passed (`ok node 0.464s`).
- `go test ./node ./internal ./crypto -run 'GroupInboxStore|GroupInboxRetrieve|HistoryRepair' -count=1` passed (`ok node 1.124s`, `ok internal 0.273s`, `ok crypto 0.557s`).
- `go test -race ./node -run 'TestGI00(5|6|7|8)GroupInboxStore' -count=1` passed (`ok node 1.770s`).
- `go test ./... -run 'GroupInbox|InboxDedup' -count=1` passed in `go-relay-server` (`ok relay-server 0.797s`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` passed (`+92`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GI-008 is now `Covered` by exact row-owned native evidence that
a failed GroupInboxStore relay stream is reset and a subsequent successful relay
stream is cleanly closed. No production runtime change was required because the
existing `streamOK` / `finishStream` path already satisfied the contract.
Residual-only: none for GI-008. Continue from GI-034, the next unresolved row in
ordered ledger order.
