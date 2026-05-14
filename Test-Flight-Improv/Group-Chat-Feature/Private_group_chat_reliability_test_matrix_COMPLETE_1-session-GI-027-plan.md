# GI-027 Session Plan: History Repair Range Required Field Validation

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-027`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:45:00 CEST | Controller | Source matrix GI-027 row; breakdown row 146; `go-mknoon/node/group_inbox.go`; existing `TestGroupHistoryRepairRange_ValidatesRequiredFields`; adjacent `GroupHistoryRepairRange` relay tests | The source row remained `Open` and the breakdown marked GI-027 `needs_code_and_tests` / `implementation-ready`. Production already trims every `GroupHistoryRepairRangeRequest` string field, defaults limit separately, and validates all required fields before node/relay work. Existing coverage only asserted one missing field, so the row-owned gap was exact proof, not missing production code. | Close with tests-only executable proof while preserving the original code-risk classification as an accepted difference. Add `TestGI027GroupHistoryRepairRangeValidatesRequiredFieldsAndTrimsWhitespace`, run focused and adjacent Go repair-range selectors, gofmt, and diff hygiene. |

## Scope

GI-027 owns `NormalizeGroupHistoryRepairRangeRequest` validation for required `groupId`, `gapId`, `sourcePeerId`, `missingAfterMessageId`, `missingBeforeMessageId`, `expectedRangeHash`, and `expectedHeadMessageId` fields, plus whitespace trimming.

Out of scope: default limit behavior (GI-028), request frame shape (GI-029), relay response metadata fallback, app-layer hash/head validation, and Flutter repair orchestration.

## Execution Contract

1. Inspect `GroupHistoryRepairRangeRequest.Validate` and `NormalizeGroupHistoryRepairRangeRequest`.
2. Add an exact row-owned Go node regression.
3. Use one valid request with surrounding whitespace on all required fields and a non-default positive limit.
4. Assert all required fields are trimmed exactly and the caller-provided positive limit remains unchanged.
5. Table-test each required field as whitespace-only and assert the field-specific missing error.
6. Run focused GI-027, adjacent `GroupHistoryRepairRange`, cursor/history selectors, gofmt, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-027 validator proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI027'` |
| Repair range selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI027|GroupHistoryRepairRange'` |
| Adjacent cursor/repair selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI011|GI012|GI027|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-027 scope is limited to the exact row-owned Go test, this plan, source matrix row GI-027, and breakdown closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:45:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI027GroupHistoryRepairRangeValidatesRequiredFieldsAndTrimsWhitespace`. The test proves all required fields are trimmed exactly, a positive caller limit is preserved, and whitespace-only `groupId`, `gapId`, `sourcePeerId`, `missingAfterMessageId`, `missingBeforeMessageId`, `expectedRangeHash`, and `expectedHeadMessageId` each fail with a field-specific missing error. | Covered the row-owned validation contract with exact Go proof; no production code change was required because existing validation already satisfied the contract. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI027'` | Passed (`ok github.com/mknoon/go-mknoon/node 1.115s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI027|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.359s`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI011|GI012|GI027|GroupInboxRetrieveWithCursor|GroupHistoryRepairRange'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.396s`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-027 is covered by exact tests-only Go node validation evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-027; continue to GI-031, the next unresolved P0 row in session order.

## Closure Bar

- Source row GI-027 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 146, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- The original `needs_code_and_tests` disposition closes as tests-only executable proof because current production already satisfies every required-field and trimming check; this is not docs-only or evidence-only closure.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
