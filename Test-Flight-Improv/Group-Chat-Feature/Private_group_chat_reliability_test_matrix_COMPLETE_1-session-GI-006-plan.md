# GI-006 Session Plan: Group Inbox Store All Relays Fail

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-006`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:57:00 CEST | Controller | Source matrix GI-006 row; breakdown row 127; `go-mknoon/node/group_inbox.go::GroupInboxStore`; `relay_selector.go`; existing generic all-relay-fail tests; existing send-use-case inbox-fail tests | The source row remains `Open`. Generic selector tests prove the wrapper error, and app tests prove adjacent pending retry behavior, but no exact GI-006 proof ties `GroupInboxStore` all-relay failure to actionable error text plus app-level no-durable/retry staging. | Add a focused Go all-relays-fail proof and a focused Flutter send-use-case proof that inbox failure leaves the message pending with retry payload and `inboxStored == false`. |

## Scope

GI-006 owns the failure contract when every configured group inbox relay fails. The node API must return an actionable all-relays-failed error after trying each relay, and the app caller must not mark durable inbox custody as stored; it must keep retry material for a later store attempt.

Out of scope: single non-OK status handling details, relay retry order success, retry worker execution, stream lifecycle reset/close, and UI status rendering.

## Execution Contract

1. Add Go test `TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail` in `go-mknoon/node/group_inbox_test.go`.
2. Configure two fake relays, both reading the request and returning non-OK; assert `GroupInboxStore` returns an error containing `all 2 relays failed` and the last actionable relay error, and assert both relays were attempted in order.
3. Add Flutter test `GI-006 inbox failure leaves message pending with retry payload and no durable mark` in `test/features/groups/application/send_group_message_use_case_test.dart`.
4. Force `group:inboxStore` to throw while `group:publish` succeeds with topic peers; assert returned and saved messages are `pending`, `inboxStored == false`, and keep `inboxRetryPayload`.
5. Run focused GI-006 Go and Flutter gates plus adjacent all-relays/inbox-fail gates, formatters, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-006 Go all-relays proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI006'` |
| Focused GI-006 Flutter retry-state proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-006'` |
| Adjacent Go relay proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI005|GI006|RelaySelector_ForEach_AllFail|GroupInboxStore'` |
| Adjacent Flutter inbox-fail proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'peers > 0 + inbox fail'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go`, `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart`, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-005 artifacts. GI-006 scope is limited to row-owned Go and Flutter tests, this plan, and closure documentation updates unless a focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:05:00 CEST | Executor | Added `go-mknoon/node/group_inbox_test.go::TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail`. The test configures two fake relays that both read the request and return non-OK, asserts `GroupInboxStore` returns an error containing `all 2 relays failed` plus the last actionable relay error, and proves attempts are exactly first then second. | Covered the node all-relays-fail contract with tests-only Go evidence. |
| 2026-05-13 04:05:00 CEST | Executor | Added `test/features/groups/application/send_group_message_use_case_test.dart::GI-006 inbox failure leaves message pending with retry payload and no durable mark`. The test forces `group:inboxStore` to throw while publish succeeds with topic peers, then proves returned/saved message status `pending`, `inboxStored == false`, retained retry payload for Bob, cleared wire envelope, and emitted inbox-store failure diagnostics. | Covered the caller retry-staging/no-durable-mark contract with tests-only Flutter evidence. |

## Verification

| Gate | Result |
|---|---|
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI006'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.489s`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-006'` | Passed (`00:00 +1: All tests passed!`). |
| `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI005\|GI006\|RelaySelector_ForEach_AllFail\|GroupInboxStore'` | Passed (`ok github.com/mknoon/go-mknoon/node 0.597s`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'peers > 0 + inbox fail'` | Passed (`00:00 +1: All tests passed!`). |
| `gofmt -w go-mknoon/node/group_inbox_test.go` | Passed. |
| `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` | Passed (`Formatted 1 file (0 changed)`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-006 is covered by exact tests-only Go and Flutter evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-006; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-006 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 127, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-006 ownership and must not mask a repo-owned blocker.
