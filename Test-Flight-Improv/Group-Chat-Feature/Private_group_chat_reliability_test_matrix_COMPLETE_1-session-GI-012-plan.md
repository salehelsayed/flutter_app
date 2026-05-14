# GI-012 Session Plan: NO_MESSAGES Empty Retrieve

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-012`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:47:00 CEST | Controller | Source matrix GI-012 row; breakdown row 131; `go-mknoon/node/group_inbox.go::groupInboxRetrieve`; existing group inbox tests | The source row remains `Open`. Production has a `NO_MESSAGES` branch that returns an empty response and marks the stream OK, but no exact row-owned regression proves the public retrieve API returns empty/no-error and closes the stream cleanly. | Add a focused Go node regression for a fake relay `NO_MESSAGES` response and verify both caller result and stream close behavior. |

## Scope

GI-012 owns the successful empty-result semantics for relay `NO_MESSAGES` responses. The row closes when a started node receives `NO_MESSAGES` from a relay and returns an empty result without error while treating the stream as successful.

Out of scope: cursor response metadata, relay retry order, non-OK statuses, malformed JSON, oversized frames, and Flutter replay application.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI012GroupInboxRetrieveNoMessagesReturnsEmptyAndClosesStream`.
2. Start a local fake relay that reads the framed request, replies `{"status":"NO_MESSAGES"}`, and then waits for the client side to close the stream.
3. Start a local node, configure the fake relay, call `GroupInboxRetrieve`, assert no error and zero returned messages.
4. Assert the request shape is the timestamp retrieve path for the requested group.
5. Assert the fake relay observes a clean EOF from the client, proving the success branch closed rather than reset the stream.
6. Run focused GI-012 and adjacent group inbox retrieve gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-012 NO_MESSAGES proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI012'` |
| Adjacent group inbox retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009|GI011|GI012|GroupInboxRetrieve|GroupInboxRetrieveWithCursorResult|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-011 artifacts. GI-012 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:54:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI012GroupInboxRetrieveNoMessagesReturnsEmptyAndClosesStream`. The test starts a local fake relay, captures the timestamp retrieve request, returns `{"status":"NO_MESSAGES"}`, asserts `GroupInboxRetrieve` returns no error and an empty message slice, and verifies the relay observes clean `io.EOF` from the client's success-path stream close. | Covered the row-owned `NO_MESSAGES` empty-success and stream-close contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI012'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.464s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009\|GI011\|GI012\|GroupInboxRetrieve\|GroupInboxRetrieveWithCursorResult\|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.417s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-012 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-012; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-012 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 131, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-012 ownership and must not mask a repo-owned blocker.
