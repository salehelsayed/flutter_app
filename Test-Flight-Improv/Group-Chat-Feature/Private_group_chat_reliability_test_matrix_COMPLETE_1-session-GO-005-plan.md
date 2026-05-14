# GO-005 Session Plan: Validation Rejection Rate Is Bounded/Deduped

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GO-005`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 07:35 CEST | Controller | Source matrix GO-005 row; breakdown session ledger row 226; existing LP-002 and GA-026 validator diagnostic tests; `go-mknoon/node/pubsub.go::logPubSubValidationReject`; app send/drain owner gates | The source row was still `Open` while the breakdown classified the row as `needs_repo_evidence`/`evidence-gated`. Production code already rate-limits validation rejection diagnostics with `pubsubAuthorizationRejectDiagnosticWindow` by reason, group id, sender id, and transport peer before emitting logs/events. Existing LP-002/GA-026 tests covered privacy and some rate limiting, but no exact GO-005 proof asserted event/log boundedness across all required key dimensions plus post-window re-emission. | Keep GO-005 as tests-only under existing production behavior, add an exact native proof for reason/group/sender/transport rate-limiting and dedupe, then run exact, adjacent, race, app-facing, and diff hygiene gates before closing the row. |

## Scope

GO-005 owns validation rejection diagnostic rate limiting for malicious or stale invalid envelopes. The row closes when repeated rejects for the same reason/group/sender/transport key emit one bounded diagnostic during the window, distinct reason/group/sender/transport dimensions still emit first diagnostics, and the same key can emit again after the configured window.

Out of scope: discovery observability (`GO-006`), topic-peer metrics (`GO-007`), broader log redaction (`GO-008`), race-detector suite policy (`GO-009`), and goroutine leak checks (`GO-010`).

## Execution Contract

1. Add an exact Go test named `TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport`.
2. Drive `logPubSubValidationReject` with a fixed clock and a test event collector.
3. Prove 50 repeated rejects for the same reason/group/sender/transport key emit one log and one `group:validation_rejected` event.
4. Prove distinct transport, sender, group, and reason values each emit their first diagnostic.
5. Prove repeated diagnostics for the new same key are deduped within the window.
6. Prove the original key emits again after `pubsubAuthorizationRejectDiagnosticWindow`.
7. Run the ledger's native race and app-facing send/drain gates.
8. Update the source matrix, breakdown ledger, and test inventory with concrete file/test/gate evidence.

## Required Gates

| Gate | Command |
|---|---|
| Format | `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go` |
| Focused GO-005 proof | `(cd go-mknoon && go test ./node -run '^TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport$' -count=1)` |
| Adjacent validator diagnostics proof | `(cd go-mknoon && go test ./node -run 'TestGO005|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons' -count=1)` |
| Native race gate | `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` |
| App-facing send/drain gate | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before closure: worktree remained dirty with prior gap-closure rollout changes and accepted session artifacts. GO-005 scope is limited to `go-mknoon/node/pubsub_authorization_forward_test.go`, this adjacent plan, source/breakdown closure updates, and test inventory entries.

## Execution Evidence

Implemented exact native row coverage in `go-mknoon/node/pubsub_authorization_forward_test.go::TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport`.

The test creates a `NewNode`, attaches a `testEventCollector`, installs a fixed `pubsubRejectDiagNow` clock, and calls `logPubSubValidationReject` directly. It proves:

- 50 repeated `non_member` rejects with the same group/sender/transport emit exactly one `group:validation_rejected` event and one log line.
- Changing transport peer, sender id, or group id emits separate first diagnostics for the same reason.
- Changing the reason to `missing_key` emits a separate first diagnostic.
- Repeating the same `missing_key` key within the window emits no additional event/log.
- Advancing by `pubsubAuthorizationRejectDiagnosticWindow + 1ns` allows the original key to emit one additional diagnostic.

Production inspected only: `go-mknoon/node/pubsub.go::logPubSubValidationReject`, including the `diagKey := strings.Join([]string{reason, groupId, senderId, pid.String()}, "|")` rate-limit key and early return before log/event/feedback emission.

No production runtime change was required.

## Verification

| Gate | Result |
|---|---|
| `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go` | Passed. |
| `(cd go-mknoon && go test ./node -run '^TestGO005ValidationRejectDiagnosticsAreRateLimitedByReasonGroupSenderTransport$' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 0.581s`. |
| `(cd go-mknoon && go test ./node -run 'TestGO005|TestLP002UnauthorizedRejectDiagnosticsArePrivacySafeAndRateLimited|TestGA026ValidationRejectDiagnosticsArePrivacySafeForAllReasons' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 0.389s`. |
| `(cd go-mknoon && go test -race ./node -run 'Group|PubSub|Relay' -count=1)` | Passed: `ok github.com/mknoon/go-mknoon/node 97.138s`. |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed: `+168 All tests passed!`. |
| `git diff --check` | Passed after closure documentation updates. |

## Final Verdict

Accepted/closed. GO-005 is covered by exact native validator diagnostic rate-limit proof plus adjacent validator diagnostics, selected native race, and app-facing send/drain gates. Residual-only none for GO-005. No final program verdict is written because unresolved rows remain.
