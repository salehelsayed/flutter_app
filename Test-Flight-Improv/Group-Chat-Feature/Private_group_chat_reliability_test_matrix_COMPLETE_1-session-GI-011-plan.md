# GI-011 Session Plan: Cursor Retrieve Page Metadata

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-011`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:31:00 CEST | Controller | Source matrix GI-011 row; breakdown row 130; `go-mknoon/node/group_inbox.go::GroupInboxRetrieveWithCursorResult`; existing `TestGroupInboxRetrieveWithCursorResult_PreservesRelayHistoryGaps` | The source row remains `Open`. Production already returns relay `Messages`, `NextCursor`, and `HistoryGaps`, and an existing test broadly covers the path, but the proof is not row-labeled and only partially asserts the preserved page fields. | Reclassify as tests-only closure: rename/enhance the existing Go node regression into an exact GI-011 proof that asserts the returned messages, next cursor, and full history-gap metadata. |

## Scope

GI-011 owns `GroupInboxRetrieveWithCursorResult` response preservation for a successful relay page. The row closes only when a relay OK page returns its `groupMessages`, `nextCursor`, and `historyGaps` through the public result object without dropping or mutating row-owned metadata.

Out of scope: non-positive limit defaults, NO_MESSAGES handling, relay stream close/reset behavior, repair range fetches, Flutter replay application, and relay persistence semantics.

## Execution Contract

1. Rename/enhance `go-mknoon/node/group_inbox_test.go::TestGroupInboxRetrieveWithCursorResult_PreservesRelayHistoryGaps` to `TestGI011GroupInboxRetrieveWithCursorResultPreservesMessagesCursorAndHistoryGaps`.
2. Keep the local fake relay and started local node fixture.
3. Return an OK cursor page with multiple `groupMessages`, a `nextCursor`, and one complete `historyGaps` entry.
4. Assert the returned result preserves message order and fields, exact next cursor, and every history-gap metadata field including candidate source peers.
5. Run focused GI-011 and adjacent group inbox retrieve/history-gap gates plus gofmt and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-011 retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI011'` |
| Adjacent group inbox retrieve proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009|GI011|GroupInboxRetrieveWithCursor|GroupInboxRetrieveWithCursorResult|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-009 artifacts. GI-011 scope is limited to the row-owned Go node regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:38:00 CEST | Executor | Renamed and enhanced `go-mknoon/node/group_inbox_test.go::TestGI011GroupInboxRetrieveWithCursorResultPreservesMessagesCursorAndHistoryGaps`. The test starts a local fake relay, captures the cursor retrieve request, returns an OK page with two `groupMessages`, a `nextCursor`, and a complete `historyGaps` entry, then asserts message order/fields, exact cursor, and every gap metadata field are preserved. | Covered the row-owned cursor result contract with tests-only Go evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI011'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.541s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI009\|GI011\|GroupInboxRetrieveWithCursor\|GroupInboxRetrieveWithCursorResult\|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.383s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-011 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-011; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-011 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 130, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-011 ownership and must not mask a repo-owned blocker.
