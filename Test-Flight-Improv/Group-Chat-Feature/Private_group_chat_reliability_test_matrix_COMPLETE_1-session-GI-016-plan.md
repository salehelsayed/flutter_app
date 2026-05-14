# GI-016 Session Plan: Retrieve Oversized Frame Rejection

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-016`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:35:00 CEST | Controller | Source matrix GI-016 row; breakdown row 135; `go-mknoon/node/node.go::readFrame`; `go-mknoon/node/group_inbox.go::groupInboxRetrieve`; existing `go-mknoon/node/group_inbox_test.go` retrieve error tests | The source row remains `Open`. Production `readFrame` rejects lengths greater than `MaxFrameLen`, but there is no exact row-owned `GI-016` proof through `GroupInboxRetrieve` that an oversized relay frame is rejected before payload allocation and no messages are returned. | Add a focused Go node regression with a local fake relay that sends only an oversized frame length prefix, proving retrieve returns a frame-too-large error through the relay selector. |

## Scope

GI-016 owns the `GroupInboxRetrieve` behavior when a relay sends a response frame length greater than `MaxFrameLen`. The row closes only when evidence proves the retrieve request reaches the relay, `readFrame` rejects the oversized frame based on the length prefix, the relay selector wrapper is preserved, and no messages are returned.

Out of scope: malformed JSON, relay non-OK status, cursor pagination, relay storage semantics, Flutter replay application, and durable send retry state.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI016GroupInboxRetrieveRejectsOversizedFrame`.
2. Start a local fake relay and configure a started node to use only that relay.
3. Capture the retrieve request and assert `action == group_retrieve`, the expected `groupId`, the caller `sinceTimestamp`, and default `limit == 50`.
4. Write a 4-byte big-endian length prefix equal to `MaxFrameLen + 1` and do not allocate or send a payload.
5. Assert `GroupInboxRetrieve` returns nil/empty messages and an error containing both the relay selector wrapper and `frame too large`.
6. Run focused GI-016 and adjacent retrieve/error gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-016 oversized frame proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI016'` |
| Adjacent group inbox retrieve/error proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI014|GI015|GI016|GroupInboxRetrieve|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-015 artifacts. GI-016 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:35:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI016GroupInboxRetrieveRejectsOversizedFrame`. The test starts one local fake relay, captures the `group_retrieve` request, writes only a 4-byte big-endian response length prefix equal to `MaxFrameLen + 1`, then asserts `GroupInboxRetrieve` returns no messages and an error containing both `all 1 relays failed` and `frame too large`. It also proves exactly one relay attempt and verifies the request group id, timestamp, action, and default limit. | Covered the row-owned oversized frame rejection contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI016'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.591s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI014\|GI015\|GI016\|GroupInboxRetrieve\|GroupInboxRetrieveWithCursor\|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.451s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-016 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-016; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-016 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 135, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-016 ownership and must not mask a repo-owned blocker.
