# GI-015 Session Plan: Retrieve Malformed JSON Error

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-015`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:25:00 CEST | Controller | Source matrix GI-015 row; breakdown row 134; `go-mknoon/node/group_inbox.go::groupInboxRetrieve`; existing `go-mknoon/node/group_inbox_test.go` retrieve error tests | The source row remains `Open`. Production has a JSON unmarshal error branch after reading the relay frame, but there is no exact row-owned `GI-015` proof that malformed relay JSON returns an actionable error and no messages. | Add a focused Go node regression with a local fake relay returning an invalid JSON frame to prove the caller receives the unmarshal error through the relay selector. |

## Scope

GI-015 owns the `GroupInboxRetrieve` behavior when the relay returns a syntactically invalid JSON response frame. The row closes only when evidence proves the retrieve request reaches the relay, malformed JSON is rejected as `unmarshal response`, the relay selector wrapper is preserved, and no messages are returned.

Out of scope: non-OK status errors, oversized frames, cursor pagination, relay storage semantics, Flutter replay application, and durable send retry state.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI015GroupInboxRetrieveMalformedJSONReturnsError`.
2. Start a local fake relay and configure a started node to use only that relay.
3. Capture the retrieve request and assert `action == group_retrieve`, the expected `groupId`, the caller `sinceTimestamp`, and default `limit == 50`.
4. Return a framed invalid JSON payload.
5. Assert `GroupInboxRetrieve` returns nil/empty messages and an error containing both the relay selector wrapper and `unmarshal response`.
6. Run focused GI-015 and adjacent retrieve/error gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-015 malformed JSON proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI015'` |
| Adjacent group inbox retrieve/error proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI014|GI015|GroupInboxRetrieve|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-014 artifacts. GI-015 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:25:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI015GroupInboxRetrieveMalformedJSONReturnsError`. The test starts one local fake relay, captures the `group_retrieve` request, returns a framed invalid JSON payload, then asserts `GroupInboxRetrieve` returns no messages and an error containing both `all 1 relays failed` and `unmarshal response`. It also proves exactly one relay attempt and verifies the request group id, timestamp, action, and default limit. | Covered the row-owned malformed relay JSON contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI015'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.586s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI014\|GI015\|GroupInboxRetrieve\|GroupInboxRetrieveWithCursor\|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.436s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-015 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-015; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-015 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 134, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-015 ownership and must not mask a repo-owned blocker.
