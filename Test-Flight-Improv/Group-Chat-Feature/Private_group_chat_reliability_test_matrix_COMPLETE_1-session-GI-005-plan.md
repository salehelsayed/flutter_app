# GI-005 Session Plan: Group Inbox Store Relay Retry Order

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-005`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:48:00 CEST | Controller | Source matrix GI-005 row; breakdown row 126; `go-mknoon/node/group_inbox.go::GroupInboxStore`; generic `RelaySelector` tests; existing all-fail group inbox retrieve tests | The source row remains `Open`. The generic relay selector proves order/fallback behavior and group inbox retrieve has all-fail coverage, but no exact `GroupInboxStore` test proves a failed first relay is followed by the second relay and that store stops after the first successful relay. | Add a focused Go node regression with two fake relays: first returns non-OK, second returns OK, and assert attempts are exactly first then second. |

## Scope

GI-005 owns `GroupInboxStore` multi-relay retry order. Store should attempt configured relays in order, continue after a failed relay response, succeed on the next OK relay, and not retry or continue after the successful relay.

Out of scope: all-relays-fail error surfacing, non-OK status detail mapping, stream reset/close lifecycle, relay storage internals, and app retry scheduling.

## Execution Contract

1. Add row-owned Go test `TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess` in `go-mknoon/node/group_inbox_test.go`.
2. Start two local libp2p fake relays with `InboxProtocol` handlers.
3. Configure the node relay list as first relay then second relay.
4. Make the first relay read the request and return `{"status":"ERROR"}`.
5. Make the second relay read the request and return `{"status":"OK"}`.
6. Assert `GroupInboxStore` returns nil and the attempt sequence is exactly `first`, `second` with no extra attempt.
7. Run focused GI-005 and adjacent relay-selector/group-inbox gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-005 retry-order proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI005'` |
| Adjacent relay/group inbox proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI005|RelaySelector_ForEach|GroupInboxStore|GroupInboxRetrieve_TriesSecondRelayWhenFirstFails'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-004 artifacts. GI-005 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless the focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 03:53:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess`. The test starts two local libp2p fake relays, configures them in order, makes the first relay read the request and return non-OK, makes the second relay read the request and return OK, and asserts `GroupInboxStore` succeeds with attempt sequence exactly `first`, `second` and no extra attempt after success. | Covered the row-owned relay retry-order contract with tests-only Go node evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI005'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.458s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI005\|RelaySelector_ForEach\|GroupInboxStore\|GroupInboxRetrieve_TriesSecondRelayWhenFirstFails'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.448s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-005 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-005; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-005 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 126, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-005 ownership and must not mask a repo-owned blocker.
