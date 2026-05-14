# GI-014 Session Plan: Retrieve Non-OK Status Error

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-014`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:15:00 CEST | Controller | Source matrix GI-014 row; breakdown row 133; `go-mknoon/node/group_inbox.go::groupInboxRetrieve`; existing `go-mknoon/node/group_inbox_test.go` retrieve tests | The source row remains `Open`. Production has a non-OK status branch returning `group inbox retrieve failed: <relay error>`, but there is no exact row-owned `GI-014` proof that a retrieve ERROR response surfaces the relay reason through the relay selector and returns no messages. | Add a focused Go node regression with a local fake relay returning `{"status":"ERROR","error":"..."}` to prove the caller receives an actionable retrieve error and no successful messages. |

## Scope

GI-014 owns the `GroupInboxRetrieve` behavior when a relay returns a non-OK status for a timestamp retrieve request. The row closes only when evidence proves the request reaches the relay, the relay error reason is included in the returned error, the relay selector wrapper is preserved, and no messages are returned.

Out of scope: malformed JSON, oversized frames, cursor pagination, all-relay failure order, durable send retry state, Flutter replay application, and relay-server storage semantics.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI014GroupInboxRetrieveReturnsRelayNonOKError`.
2. Start a local fake relay and configure a started node to use only that relay.
3. Capture the retrieve request and assert `action == group_retrieve`, the expected `groupId`, the caller `sinceTimestamp`, and default `limit == 50`.
4. Return relay status `ERROR` with a row-owned reason string.
5. Assert `GroupInboxRetrieve` returns nil/empty messages and an error containing both the relay selector wrapper and `group inbox retrieve failed: <reason>`.
6. Run focused GI-014 and adjacent retrieve/error gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-014 non-OK retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI014'` |
| Adjacent group inbox retrieve/error proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI012|GI013|GI014|GroupInboxRetrieve|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-013 artifacts. GI-014 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:15:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI014GroupInboxRetrieveReturnsRelayNonOKError`. The test starts one local fake relay, captures the `group_retrieve` request, returns `{"status":"ERROR","error":"retrieve quota exceeded for group"}`, then asserts `GroupInboxRetrieve` returns no messages and an error containing both `all 1 relays failed` and `group inbox retrieve failed: retrieve quota exceeded for group`. It also proves exactly one relay attempt and verifies the request group id, timestamp, action, and default limit. | Covered the row-owned retrieve non-OK status contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI014'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.570s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI012\|GI013\|GI014\|GroupInboxRetrieve\|GroupInboxRetrieveWithCursor\|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.466s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-014 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-014; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-014 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 133, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-014 ownership and must not mask a repo-owned blocker.
