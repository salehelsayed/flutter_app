# Private Group Chat Reliability Matrix - Session GK-031 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 23:45 CEST - Local gap-closure pass reached GK-031 after GK-028 closure. Source matrix row GK-031 was `Open`; session ledger row 191 was `implementation-ready` / `needs_tests_only`; no adjacent GK-031 plan existed. Inspected the source row, session ledger, `go-mknoon/node/pubsub.go::PublishGroupMessage`, `buildGroupMessageExtra`, existing extra-field and message-id tests in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_delivery_test.go`.
- 2026-05-13 23:46 CEST - Added exact pure helper and live publish/receive GK-031 regressions. Current production behavior already writes explicit `messageId` last, so closure is tests-only. Updated source matrix, breakdown, and test inventory evidence; GK-032 is next in ledger order.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GK-031 | messageId cannot be overridden through opts | Covered | covered/accepted |

## Gap Classification

`needs_tests_only`.

Current production behavior already writes the explicit `messageId` after copying `opts` in `buildGroupMessageExtra`, and `PublishGroupMessage` returns the explicit id when provided. The row-owned gap is missing exact GK-031 proof that a conflicting `opts.messageId` cannot override the explicit id in the unit helper or live publish/receive event path.

## Scope

Owned files:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Production runtime changes unless exact proof exposes a behavior gap.
- Dart/Flutter replay changes; the source row is owned by the Go publish payload construction path.
- Device-lab or relay-backed harness changes unless host publish proof exposes missing runtime behavior.

## Implementation Plan

1. Add an exact pure Go unit regression for `buildGroupMessageExtra` proving explicit `messageId` overwrites conflicting `opts.messageId` without mutating input opts.
2. Add an exact live Go publish/receive regression proving `PublishGroupMessage` returns, logs, and delivers the explicit id even when opts contain a conflicting `messageId`, while preserving unrelated opts.
3. Run focused GK-031 tests, adjacent publish/message-id selectors, broader Go owner selector, gofmt, and diff hygiene.
4. Update the source matrix, breakdown ledger, plan verdict, and test inventory with concrete evidence before accepting the row.

## Acceptance Bar

- Source matrix row GK-031 is `Covered`.
- Session ledger row 191 is `covered/accepted`.
- Tests include exact `GK-031` selectors for unit helper and live publish/receive behavior.
- Evidence records focused selectors, adjacent Go gates, and `git diff --check`.
- Residual-only entry is `none`; no unresolved row-owned blocker remains.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGK031BuildGroupMessageExtraExplicitMessageIDWins`.
- Added `go-mknoon/node/pubsub_delivery_test.go::TestGK031PublishGroupMessageExplicitMessageIDWinsOverOptsMessageID`.
- Validation passed: gofmt, focused GK-031 (`ok node 0.683s`), adjacent publish/message-id selector (`ok node 3.389s`), broader node/internal/crypto selector (`ok node 2.590s`, `ok internal 1.252s`, `ok crypto 0.935s`), selected race selector (`ok node 4.093s`), and named `./scripts/run_test_gates.sh groups` (`+159`).

## Final Verdict

Accepted/closed. GK-031 is `Covered` in the source matrix and `covered/accepted` in session ledger row 191. No production runtime change was required because the current Go payload construction already writes the explicit `messageId` after copying opts; the new row-owned tests prove conflicting `opts.messageId` cannot override that id in unit and live publish/receive paths. Residual-only: none. Continue with GK-032.
