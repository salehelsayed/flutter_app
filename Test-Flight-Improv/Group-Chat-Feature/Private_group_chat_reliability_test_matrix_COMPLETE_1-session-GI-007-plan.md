# GI-007 Session Plan: Group Inbox Store Relay Non-OK Status

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-007`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:09:00 CEST | Controller | Source matrix GI-007 row; breakdown row 128; `go-mknoon/node/group_inbox.go::GroupInboxStore`; existing inbox ok:false app test | The source row remains `Open`. Production maps non-OK relay responses to `group inbox store failed: <error>`, and Flutter treats `group:inboxStore` ok:false as inbox failure, but no exact GI-007 row proof asserts the node error plus app retry/no-durable state. | Add focused Go and Flutter regressions for relay non-OK status. |

## Scope

GI-007 owns the non-OK relay response path for group inbox store. A relay response with `status != OK` must produce an actionable node error, and the app must treat the bridge ok:false result as failed durable custody while retaining retry material.

Out of scope: all relays failing, relay retry order, stream reset/close lifecycle, retry worker execution, and UI status rendering.

## Execution Contract

1. Add Go test `TestGI007GroupInboxStoreReturnsRelayNonOKError` in `go-mknoon/node/group_inbox_test.go`.
2. Start one fake relay that reads the request and returns `{"status":"ERROR","error":"quota exceeded"}`.
3. Assert `GroupInboxStore` returns an error containing `group inbox store failed: quota exceeded` and that the relay was attempted once.
4. Add Flutter test `GI-007 relay non-OK status leaves message pending with retry payload` using `_InboxStoreOkFalseBridge`.
5. Assert returned/saved messages are `pending`, `inboxStored == false`, retry payload retained, and no durable mark is applied.
6. Run focused GI-007 Go/Flutter gates plus adjacent non-OK/inbox-fail gates, formatters, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-007 Go non-OK proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI007'` |
| Focused GI-007 Flutter ok:false proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-007'` |
| Adjacent Go group inbox status proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI006|GI007|GroupInboxStore'` |
| Adjacent Flutter ok:false proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'inbox store ok:false is treated as inbox failure'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go`, `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart`, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-006 artifacts. GI-007 scope is limited to row-owned Go and Flutter tests, this plan, and closure documentation updates unless a focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:13:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI007GroupInboxStoreReturnsRelayNonOKError`. The test starts one fake relay returning `{"status":"ERROR","error":"quota exceeded"}`, asserts `GroupInboxStore` returns the selector wrapper plus `group inbox store failed: quota exceeded`, and verifies exactly one relay attempt. | Covered the node relay non-OK status contract with tests-only Go evidence. |
| 2026-05-13 04:13:00 CEST | Executor | Added `test/features/groups/application/send_group_message_use_case_test.dart::GI-007 relay non-OK status leaves message pending with retry payload`. The test uses `_InboxStoreOkFalseBridge`, publish succeeds, and returned/saved messages stay `pending`, `inboxStored == false`, and retain retry payload for Bob. | Covered the app ok:false retry/no-durable state with tests-only Flutter evidence. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI007'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.526s`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-007'` | Passed (`00:00 +1: All tests passed!`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI006\|GI007\|GroupInboxStore'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.422s`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'inbox store ok:false is treated as inbox failure'` | Passed (`00:00 +1: All tests passed!`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` | Passed (`Formatted 1 file (0 changed)`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-007 is covered by exact tests-only Go and Flutter evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-007; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-007 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 128, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-007 ownership and must not mask a repo-owned blocker.
