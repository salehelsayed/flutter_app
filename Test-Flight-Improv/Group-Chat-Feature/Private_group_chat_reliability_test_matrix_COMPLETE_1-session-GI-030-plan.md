# GI-030 Session Plan: Repair Response Fallback IDs

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-030`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 02:42 CEST | Controller | Source matrix GI-030 row; breakdown session ledger row 209; `go-mknoon/node/group_inbox.go::GroupHistoryRepairRange`; adjacent GI-029 request-shape proof; existing repair-range tests; test inventory Group Inbox section | The source row remained `Open` and no adjacent GI-030 plan existed. Production already falls back missing response `groupId`, `gapId`, and `sourcePeerId` from the normalized request, but no exact row-named proof made the relay omit those fields and asserted the returned response used request values. | Add exact row-owned Go node proof that captures the normalized repair request, returns a relay repair response missing `groupId`, `gapId`, and `sourcePeerId`, and proves the final response uses normalized request IDs while preserving relay integrity metadata and replay messages. |

## Scope

GI-030 owns the native `GroupHistoryRepairRange` response metadata fallback contract. When a relay returns an otherwise OK repair-range response that omits `groupId`, `gapId`, or `sourcePeerId`, the node response must fill those fields from the normalized request values.

Out of scope: required-field validation, request default limit behavior, outbound request-shape coverage, range hash mismatch rejection, repair source authorization, app repair orchestration, and notification behavior.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs`.
2. Start a local libp2p fake relay that captures the framed `group_history_repair_range` request.
3. Send a valid repair-range request with whitespace-padded `groupId`, `gapId`, `sourcePeerId`, boundary, hash, and head fields.
4. Have the relay return OK with `rangeHash`, `headMessageId`, and one replay envelope while omitting `groupId`, `gapId`, and `sourcePeerId`.
5. Assert the final response fills `GroupId`, `GapId`, and `SourcePeerId` from normalized request values, keeps relay `RangeHash` and `HeadMessageId`, and preserves the replay message.
6. Run focused GI-030, adjacent repair-range, broader inbox/history, relay-server, app inbox, selected race, named groups, format, and diff hygiene gates.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-030 native proof | `cd go-mknoon && go test ./node -run '^TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs$' -count=1` |
| Adjacent repair-range proof | `cd go-mknoon && go test ./node -run 'GI027\|GI028\|GI029\|GI030\|GroupHistoryRepairRange' -count=1` |
| Broader inbox/history native proof | `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|GroupHistoryRepairRange\|HistoryRepair' -count=1` |
| Relay-server inbox proof | `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` |
| Flutter app-side inbox proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` |
| Selected race proof | `cd go-mknoon && go test -race ./node -run 'GI027\|GI028\|GI029\|GI030\|GroupHistoryRepairRange' -count=1` |
| Named groups gate | `./scripts/run_test_gates.sh groups` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GI-030 scope is limited to the exact row-owned native regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 02:42 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs`. The test starts a local fake relay, captures the normalized repair request, returns an OK repair response that omits `groupId`, `gapId`, and `sourcePeerId`, then proves the node response fills those IDs from the normalized request while preserving relay `rangeHash`, `headMessageId`, and the replay message. | Covered the row-owned repair-response fallback contract with tests-only Go evidence; no production code change required because `GroupHistoryRepairRange` already fills missing response IDs from the normalized request. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run '^TestGI030GroupHistoryRepairRangeResponseFallsBackToRequestIDs$' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.540s`). |
| `cd go-mknoon && go test ./node -run 'GI027\|GI028\|GI029\|GI030\|GroupHistoryRepairRange' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.517s`). |
| `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|GroupHistoryRepairRange\|HistoryRepair' -count=1` | Passed (`ok node 0.596s`, `ok internal 0.681s [no tests to run]`, `ok crypto 0.999s [no tests to run]`). |
| `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` | Passed (`ok github.com/mknoon/relay-server 0.828s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | Passed (`+92 All tests passed`). |
| `cd go-mknoon && go test -race ./node -run 'GI027\|GI028\|GI029\|GI030\|GroupHistoryRepairRange' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 1.720s`). |
| `./scripts/run_test_gates.sh groups` | Passed (`+160 All tests passed`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-030 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-030; GI-034 is the next unresolved session in ordered ledger order.

## Closure Bar

- Source row GI-030 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row inventory, row disposition, session ledger row 209, ordered row 209, closure progress, and session closure ledger are updated to `covered/accepted`.
- Test inventory includes the added GI-030 Go Group Inbox test and aggregate count updates.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-030 ownership and must not mask a repo-owned blocker.
