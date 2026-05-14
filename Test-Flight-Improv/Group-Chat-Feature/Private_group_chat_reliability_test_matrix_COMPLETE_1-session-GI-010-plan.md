# GI-010 Session Plan: Cursor Retrieve Non-Positive Limit Default

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-010`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 02:24 CEST | Controller | Source matrix GI-010 row; breakdown session ledger row 207; `go-mknoon/node/group_inbox.go::GroupInboxRetrieveWithCursorResult`; existing `TestGroupInboxRetrieveCursor_DefaultsLimitWhenZero` and `TestGroupInboxRetrieveCursor_NegativeLimitDefaultsTo50`; test inventory cursor entries | The source row remained `Open` and no adjacent GI-010 plan existed. Production already normalizes `limit <= 0` to `50`, but the legacy tests only proved the call reached fake relays and did not capture the framed request or prove opaque cursor preservation for both `0` and `-1`. | Add exact row-owned Go node proof that captures real relay-visible cursor retrieve requests for both non-positive limits, asserts `limit == 50`, and asserts each caller cursor is preserved. |

## Scope

GI-010 owns the native cursor retrieve request-shape defaulting contract. A started node calling `GroupInboxRetrieveWithCursor` with `limit == 0` or `limit < 0` must send `action == group_retrieve_cursor`, preserve the caller's opaque cursor string, and set `limit == 50` in the relay-visible request.

Out of scope: timestamp-based retrieve defaults, cursor page response metadata, relay persistence, Flutter drain pagination, and history repair range behavior.

## Execution Contract

1. Add `go-mknoon/node/group_inbox_test.go::TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor`.
2. Start a local fake relay that captures each framed `InboxProtocol` request and returns `{"status":"OK","groupMessages":[]}`.
3. Call `GroupInboxRetrieveWithCursor` once with `limit == 0` and cursor `cursor-gi-010-zero`, then once with `limit == -1` and cursor `cursor-gi-010-negative`.
4. Assert each captured request has `action == group_retrieve_cursor`, `groupId == group-gi-010`, the exact caller cursor, and `limit == 50`.
5. Run focused GI-010, adjacent cursor retrieve, broader inbox/history, relay-server, app inbox, selected race, named groups, format, and diff hygiene gates.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-010 native proof | `cd go-mknoon && go test ./node -run '^TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor$' -count=1` |
| Adjacent cursor retrieve proof | `cd go-mknoon && go test ./node -run 'Test(GI009\|GI010\|GI011)\|TestGroupInboxRetrieveCursor_(DefaultsLimitWhenZero\|NegativeLimitDefaultsTo50\|StableAcrossPages\|NoDuplicateOnContinuation\|RequiresStartedNode)' -count=1` |
| Broader inbox/history native proof | `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|HistoryRepair' -count=1` |
| Relay-server inbox proof | `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` |
| Flutter app-side inbox proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` |
| Selected race proof | `cd go-mknoon && go test -race ./node -run 'TestGI010\|TestGroupInboxRetrieveCursor_(DefaultsLimitWhenZero\|NegativeLimitDefaultsTo50)' -count=1` |
| Named groups gate | `./scripts/run_test_gates.sh groups` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GI-010 scope is limited to the exact row-owned native regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 02:24 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor`. The test starts a local fake relay, captures two framed cursor retrieve requests, returns OK empty pages, and proves both `limit == 0` and `limit == -1` become relay-visible `limit == 50` while preserving distinct opaque cursor strings. | Covered the row-owned cursor request defaulting contract with tests-only Go evidence; no production code change required because `GroupInboxRetrieveWithCursorResult` already normalizes non-positive limits. |

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `cd go-mknoon && go test ./node -run '^TestGI010GroupInboxRetrieveWithCursorDefaultsNonPositiveLimitAndPreservesCursor$' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.485s`). |
| `cd go-mknoon && go test ./node -run 'Test(GI009\|GI010\|GI011)\|TestGroupInboxRetrieveCursor_(DefaultsLimitWhenZero\|NegativeLimitDefaultsTo50\|StableAcrossPages\|NoDuplicateOnContinuation\|RequiresStartedNode)' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.477s`). |
| `cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupInboxRetrieve\|GroupInboxRetrieveCursor\|HistoryRepair' -count=1` | Passed (`ok node 0.812s`, `ok internal 1.167s [no tests to run]`, `ok crypto 0.901s [no tests to run]`). |
| `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` | Passed (`ok github.com/mknoon/relay-server 0.816s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | Passed (`+92 All tests passed`). |
| `cd go-mknoon && go test -race ./node -run 'TestGI010\|TestGroupInboxRetrieveCursor_(DefaultsLimitWhenZero\|NegativeLimitDefaultsTo50)' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 1.866s`). |
| `./scripts/run_test_gates.sh groups` | Passed (`+160 All tests passed`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-010 is covered by exact tests-only Go node evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-010; GI-034 is the next unresolved session in ordered ledger order.

## Closure Bar

- Source row GI-010 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row inventory, row disposition, session ledger row 207, ordered row 207, closure progress, and session closure ledger are updated to `covered/accepted`.
- Test inventory includes the added GI-010 Go Group Inbox test and aggregate count updates.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-010 ownership and must not mask a repo-owned blocker.
