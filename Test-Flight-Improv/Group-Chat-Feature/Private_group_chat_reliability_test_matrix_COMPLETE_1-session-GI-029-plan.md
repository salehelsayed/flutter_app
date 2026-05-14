# GI-029 Session Plan: History Repair Range Request Shape

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-029`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:50:00 CEST | Controller | Source matrix GI-029 row; breakdown row 147; existing `TestGroupHistoryRepairRange_ReturnsRelayReplayEnvelopes`; `go-mknoon/node/group_inbox.go::GroupHistoryRepairRange` | The source row is `Open` and the breakdown marks GI-029 `needs_tests_only` / `implementation-ready`. Production already builds `group_history_repair_range` with normalized group/gap/source/boundary/hash/head/limit fields, and the adjacent existing test only asserts action plus hash/head. | Add an exact row-owned Go node regression that captures the fake-relay JSON request and asserts the full action, boundary, integrity, source, and limit shape. |

## Scope

GI-029 owns the JSON request shape sent by `GroupHistoryRepairRange` to the relay inbox action.

Out of scope: required-field validation and whitespace errors (GI-027), default limit behavior (GI-028), relay response metadata fallback, Flutter repair orchestration, relay-side response validation, and history hash verification.

## Execution Contract

1. Inspect the existing Go repair range request builder and relay test.
2. Add `TestGI029GroupHistoryRepairRangeSendsExpectedRequestShape`.
3. Use a fake relay stream handler to capture the marshaled `groupInboxRequest`.
4. Call `GroupHistoryRepairRange` with all row-owned fields and a non-default positive limit.
5. Assert action `group_history_repair_range`, normalized group/gap/source, missing-after/before boundaries, expected hash/head, and limit.
6. Run focused GI-029, adjacent repair-range/cursor selectors, gofmt, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-029 request proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI029'` |
| Repair range selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI027|GI029|GroupHistoryRepairRange'` |
| Adjacent cursor/repair selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI011|GI012|GI027|GI029|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-029 scope is limited to the exact row-owned Go test, this plan, source matrix row GI-029, and breakdown closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:50:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI029GroupHistoryRepairRangeSendsExpectedRequestShape`. The test starts a local libp2p fake relay, captures the framed `groupInboxRequest` written by `GroupHistoryRepairRange`, passes whitespace-padded group/gap/source/boundary/hash/head fields with caller limit `37`, and asserts action `group_history_repair_range`, normalized group/gap/source, missing-after/before boundaries, expected hash/head, and limit `37`. | Covered the row-owned request-shape contract with exact Go proof; no production code change was required because existing request construction already satisfied the contract. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI029'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.472s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI027|GI029|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.365s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI011|GI012|GI027|GI029|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.389s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-029 is covered by exact tests-only Go node request-shape evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-029; continue to GI-031, the next unresolved P0 row in session order.

## Closure Bar

- Source row GI-029 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 147, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- The original tests-only disposition closes with executable Go request-shape proof.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
