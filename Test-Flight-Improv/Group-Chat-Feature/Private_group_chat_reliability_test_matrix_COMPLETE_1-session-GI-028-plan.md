# GI-028 Session Plan: Repair Range Non-Positive Limit Default

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-028`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 02:33 CEST | Controller | Source matrix GI-028 row; breakdown session ledger row 208; `go-mknoon/node/group_inbox.go::NormalizeGroupHistoryRepairRangeRequest`; adjacent repair-range tests `GI-027` and `GI-029`; test inventory Group Inbox section | The source row remained `Open` and no adjacent GI-028 plan existed. Production already normalizes `Limit <= 0` to `50`, but existing repair-range tests covered required-field validation and outbound request shape without an exact row-named proof for both zero and negative limits. | Add exact row-owned Go node proof that normalizes valid repair-range requests with `Limit == 0` and `Limit == -1`, proves both become `50`, and proves all non-limit fields remain unchanged. |

## Scope

GI-028 owns the native `GroupHistoryRepairRange` request normalization contract. A valid repair-range request with `Limit == 0` or `Limit < 0` must normalize to `Limit == 50` before node or relay work while preserving normalized request identity fields.

Out of scope: required-field validation, relay request framing, repair response metadata fallback, range hash validation, app repair orchestration, and cursor inbox pagination.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50`.
2. Build a valid `GroupHistoryRepairRangeRequest` with non-empty group, gap, source, boundary, expected hash, and expected head fields.
3. Normalize a request with `Limit == 0` and one with `Limit == -1`.
4. Assert both normalized requests have `Limit == 50`.
5. Assert all non-limit request fields are preserved exactly.
6. Run focused GI-028, adjacent repair-range, broader inbox/history, relay-server, app inbox, selected race, named groups, format, and diff hygiene gates.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-028 native proof | `cd go-mknoon && go test ./node -run '^TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50$' -count=1` |
| Adjacent repair-range proof | `cd go-mknoon && go test ./node -run 'GI027\|GI028\|GI029\|GroupHistoryRepairRange' -count=1` |
| Broader inbox/history native proof | `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|GroupHistoryRepairRange\|HistoryRepair' -count=1` |
| Relay-server inbox proof | `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` |
| Flutter app-side inbox proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` |
| Selected race proof | `cd go-mknoon && go test -race ./node -run 'GI027\|GI028\|GI029\|GroupHistoryRepairRange' -count=1` |
| Named groups gate | `./scripts/run_test_gates.sh groups` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure documentation: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GI-028 scope is limited to the exact row-owned native regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 02:33 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50`. The test normalizes valid repair-range requests with `Limit == 0` and `Limit == -1`, proves both become `50`, and proves group/gap/source/boundary/hash/head fields remain unchanged. | Covered the row-owned repair-range defaulting contract with tests-only Go evidence; no production code change required because `NormalizeGroupHistoryRepairRangeRequest` already defaults non-positive limits. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run '^TestGI028GroupHistoryRepairRangeDefaultsNonPositiveLimitTo50$' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.570s`). |
| `cd go-mknoon && go test ./node -run 'GI027\|GI028\|GI029\|GroupHistoryRepairRange' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.470s`). |
| `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|GroupHistoryRepairRange\|HistoryRepair' -count=1` | Passed (`ok node 0.922s`, `ok internal 1.029s [no tests to run]`, `ok crypto 0.418s [no tests to run]`). |
| `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` | Passed (`ok github.com/mknoon/relay-server 0.782s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | Passed (`+92 All tests passed`). |
| `cd go-mknoon && go test -race ./node -run 'GI027\|GI028\|GI029\|GroupHistoryRepairRange' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 1.931s`). |
| `./scripts/run_test_gates.sh groups` | Passed (`+160 All tests passed`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-028 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-028; GI-034 is the next unresolved session in ordered ledger order.

## Closure Bar

- Source row GI-028 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row inventory, row disposition, session ledger row 208, ordered row 208, closure progress, and session closure ledger are updated to `covered/accepted`.
- Test inventory includes the added GI-028 Go Group Inbox test and aggregate count updates.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-028 ownership and must not mask a repo-owned blocker.
