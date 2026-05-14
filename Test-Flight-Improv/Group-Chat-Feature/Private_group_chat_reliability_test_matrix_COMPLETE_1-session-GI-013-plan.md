# GI-013 Session Plan: Retrieve Relay Retry Order

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-013`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:00:00 CEST | Controller | Source matrix GI-013 row; breakdown row 132; `go-mknoon/node/group_inbox.go::groupInboxRetrieve`; existing `go-mknoon/node/multi_relay_test.go::TestGroupInboxRetrieve_TriesSecondRelayWhenFirstFails` | The source row remains `Open`. Existing multi-relay coverage proves only that multiple unreachable fake relays are attempted before an all-relays error; it does not prove first-relay failure followed by second-relay success and returned data. | Add a focused Go node regression with two real local fake relays: first returns non-OK, second returns OK with messages, and the caller receives the second relay data. |

## Scope

GI-013 owns `GroupInboxRetrieve` relay failover for the successful second-relay path. The row closes only when the test proves ordered retry, overall success, returned data from the second relay, and no extra relay attempt after success.

Out of scope: cursor retrieve failover, all-relay failure errors, non-OK final errors, malformed JSON, NO_MESSAGES, and Flutter replay application.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI013GroupInboxRetrieveRetriesRelaysInOrderAndReturnsSecondData`.
2. Start two local fake relays and configure the node relay list as first then second.
3. Make the first relay read the request and return non-OK.
4. Make the second relay read the request and return OK with group inbox messages.
5. Assert `GroupInboxRetrieve` succeeds, returns the second relay message fields, attempts relays in order, and does not attempt any extra relay after success.
6. Run focused GI-013 and adjacent retrieve failover gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-013 retrieve failover proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI013'` |
| Adjacent group inbox retrieve failover proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI012|GI013|GroupInboxRetrieve_TriesSecondRelayWhenFirstFails|GroupInboxRetrieveWithCursor_TriesSecondRelayWhenFirstFails|GroupInboxRetrieve|RelaySelector_ForEachWithResult'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-012 artifacts. GI-013 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:05:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI013GroupInboxRetrieveRetriesRelaysInOrderAndReturnsSecondData`. The test starts two local fake relays, makes the first read the `group_retrieve` request and return non-OK, makes the second read the same retrieve request and return OK with one message, then asserts the caller receives the second relay message intact, attempts are `[first, second]`, and no extra relay is attempted after success. | Covered the row-owned retrieve failover success contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI013'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.670s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI012\|GI013\|GroupInboxRetrieve_TriesSecondRelayWhenFirstFails\|GroupInboxRetrieveWithCursor_TriesSecondRelayWhenFirstFails\|GroupInboxRetrieve\|RelaySelector_ForEachWithResult'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.419s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-013 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-013; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-013 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 132, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-013 ownership and must not mask a repo-owned blocker.
