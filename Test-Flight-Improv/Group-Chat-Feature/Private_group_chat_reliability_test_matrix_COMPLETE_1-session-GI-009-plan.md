# GI-009 Session Plan: Group Inbox Retrieve Since Timestamp Request

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-009`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:17:00 CEST | Controller | Source matrix GI-009 row; breakdown row 130; `go-mknoon/node/group_inbox.go::GroupInboxRetrieve`; existing cursor retrieve request tests | The source row remains `Open`. Production builds a `group_retrieve` request with `sinceTimestamp` and default `limit == 50`, but existing tests focus on cursor retrieve/default limit and do not capture the timestamp-based framed request. | Add a focused Go node regression that captures the relay-visible `GroupInboxRetrieve` request and asserts `action`, `groupId`, `sinceTimestamp`, and `limit`. |

## Scope

GI-009 owns timestamp-based `GroupInboxRetrieve` request serialization. A started node must send a framed JSON request with `action == group_retrieve`, the requested group id, the caller-provided unix-millis `sinceTimestamp`, and default `limit == 50`.

Out of scope: cursor pagination defaults, history repair, relay authorization, replay application, and Flutter drain behavior.

## Execution Contract

1. Add Go test `TestGI009GroupInboxRetrieveSendsSinceTimestampRequestShape` in `go-mknoon/node/group_inbox_test.go`.
2. Start a local fake relay that reads one `InboxProtocol` frame and returns an OK response with an empty `groupMessages` array.
3. Start a local node, configure the fake relay, call `GroupInboxRetrieve` with a fixed `sinceTimestamp`, and assert no error.
4. Assert the captured request has `action == group_retrieve`, matching `groupId`, matching `sinceTimestamp`, and `limit == 50`.
5. Run focused GI-009 and adjacent retrieve gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-009 retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI009'` |
| Adjacent group inbox retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009|GroupInboxRetrieve|GroupInboxRetrieveCursor_DefaultsLimitWhenZero|GroupInboxRetrieveWithCursorResult_PreservesRelayHistoryGaps'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-007 artifacts. GI-009 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless a focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:21:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI009GroupInboxRetrieveSendsSinceTimestampRequestShape`. The test starts a local fake relay, captures the framed request from `GroupInboxRetrieve`, returns an OK empty page, and asserts `action == group_retrieve`, expected `groupId`, exact caller `sinceTimestamp`, and default `limit == 50`. | Covered the row-owned timestamp retrieve request-shape contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI009'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.581s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009\|GroupInboxRetrieve\|GroupInboxRetrieveCursor_DefaultsLimitWhenZero\|GroupInboxRetrieveWithCursorResult_PreservesRelayHistoryGaps'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.404s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-009 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-009; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-009 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 130, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-009 ownership and must not mask a repo-owned blocker.
