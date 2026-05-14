# GI-017 Session Plan: Offline Replay Drains All Paginated Entitled Messages

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-017`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:45:00 CEST | Controller | Source matrix GI-017 row; breakdown row 136; relay cursor tests in `go-relay-server/group_inbox_test.go`; app drain pagination tests in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `drain_group_offline_inbox_use_case.dart` cursor loop | The source row remains `Open`. Existing relay tests prove smaller cursor pagination, and existing app tests prove a two-page continuation, but no exact row-owned proof covers the release-gate shape: 120 entitled group inbox messages across default-size pages, drained once, in order, and deduped on repeat drain. | Add exact row-owned relay and Flutter app regressions: relay authorized cursor pagination for 120 recipient-entitled messages, and app offline drain applying 120 signed replay messages across three cursor pages exactly once. |

## Scope

GI-017 owns the offline replay pagination contract for more-than-one-page group inbox retrieval. The row closes only when evidence proves all 120 entitled messages are retrievable across cursor pages, the app follows the returned cursors, persists all messages once in chronological order, advances/clears the cursor at completion, and re-drain does not duplicate messages.

Out of scope: removed/re-added membership windows, non-member replay authorization, device revocation replay, key epoch grace, duplicate replay attack bounds, history-gap repair, and real simulator/device relay fixtures.

## Execution Contract

1. Add `go-relay-server/group_inbox_test.go::TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce`.
2. Store 120 group inbox messages for recipient `peer-b`, retrieve as `peer-b` with cursor page size 50, and assert 3 pages, all 120 IDs/messages in order, no duplicates, and empty final cursor.
3. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-017 offline member drains 120 entitled messages across pages exactly once`.
4. Seed 120 signed replay messages across three fake bridge cursor pages, drain the group inbox, and assert three cursor requests (`''`, `cursor-050`, `cursor-100`), default page size 50, no sinceTimestamp fallback, 120 saved messages in chronological/id order, final cursor cleared, and repeat drain leaves the count at 120.
5. Run focused GI-017 Go and Flutter gates, adjacent relay/app pagination selectors, formatters, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-017 relay pagination proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./... -run 'TestGI017'` from `go-relay-server` |
| Focused GI-017 app drain proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-017'` |
| Adjacent relay pagination proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./... -run 'CursorPagination|RetrieveWithCursor|GI017'` from `go-relay-server` |
| Adjacent app drain pagination proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'cursor continuation'` |
| Hygiene | `gofmt -w go-relay-server/group_inbox_test.go`; `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-016 artifacts. GI-017 scope is limited to row-owned relay and Flutter pagination regressions, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:45:00 CEST | Executor | Added `go-relay-server/group_inbox_test.go::TestGI017GroupInboxStoreAuthorizedCursorPaginationReturns120MessagesExactlyOnce`. The test stores 120 messages for recipient `peer-b`, retrieves as `peer-b` with cursor page size 50, proves exactly 3 pages, all 120 messages in order, no duplicate IDs, recipient authorization for every returned row, and no results for unauthorized `peer-c`. | Covered relay-side entitlement and cursor pagination for the 120-message release-gate shape. |
| 2026-05-13 05:45:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-017 offline member drains 120 entitled messages across pages exactly once`. The test seeds three signed replay pages (50/50/20), proves app cursor requests `''`, `cursor-050`, and `cursor-100` with limit 50 and no `sinceTimestamp`, saves all 120 messages in chronological/id order, clears the final cursor, and repeat drain leaves count at 120. | Covered app offline replay pagination, application, cursor completion, and dedupe behavior. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./... -run 'TestGI017'` from `go-relay-server` | Passed (`ok github.com/mknoon/relay-server 0.601s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-017'` | Passed (`+1`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./... -run 'CursorPagination\|RetrieveWithCursor\|GI017'` from `go-relay-server` | Passed (`ok github.com/mknoon/relay-server 0.441s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'cursor continuation'` | Passed (`+1`). |
| `gofmt -w go-relay-server/group_inbox_test.go` | Passed. |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-017 is covered by exact relay and Flutter app evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-017; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-017 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 136, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-017 ownership and must not mask a repo-owned blocker.
