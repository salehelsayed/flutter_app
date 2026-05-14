# GP-023 Session Plan: Malformed Receive Does Not Stop Handler

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-023`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 02:02:00 CEST | Controller | Source matrix GP-023 row; breakdown row 118; production `go-mknoon/node/pubsub.go::handleGroupSubscription`, `internal.ParseGroupPayload`, and `emitGroupPayloadParseFailed`; existing malformed payload tests GK-029 and basic parse-failure tests | Existing tests prove malformed payload diagnostics and no bad-message render, but the row remains open because no exact row-owned proof delivers malformed traffic and then a valid message through the same live subscription to prove the handler continues. | Add exact Go node regression `TestGP023ReceivePathContinuesAfterMalformedPayload`. No production code change is expected unless the test exposes handler exit. |
| 2026-05-13 02:10:00 CEST | Controller | Source matrix GP-023 row, breakdown row 118, added `go-mknoon/node/pubsub_decryption_failure_test.go::TestGP023ReceivePathContinuesAfterMalformedPayload`, focused and adjacent Go gate output, gofmt, and `git diff --check` | The exact row-owned live receive proof now exists and passes. Existing production already continues the subscription loop after malformed payload parse failure. | Close GP-023 as `Covered`/accepted with tests-only Go node proof and no production code change. Continue from GI-031, the next unresolved P0 row. |

## Scope

GP-023 owns the Go node subscription loop continuation contract after malformed group message traffic. A malformed decrypted payload must be skipped without terminating the handler; later valid messages on the same subscription must still emit.

Out of scope: decryption failure diagnostics, app-layer dedupe, subscription `sub.Next` transport errors, and UI persistence ordering.

## Execution Contract

1. Add row-owned Go regression `TestGP023ReceivePathContinuesAfterMalformedPayload`.
2. Publish a valid signed/encrypted group envelope whose decrypted `group_message` plaintext is malformed/non-JSON.
3. Assert the receiver emits `group:payload_parse_failed` and no `group_message:received` for the bad plaintext.
4. Publish a valid signed/encrypted group message on the same subscription.
5. Assert the valid later message emits `group_message:received` with the expected message id/text, proving the handler did not exit.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-023 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP023')` |
| Adjacent malformed receive selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP023|GK029|PayloadParseFailed|MalformedPayload|HandleGroupSubscription')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-022 closure artifacts. GP-023 scope is limited to row-owned Go tests, this plan, and closure documentation updates unless the focused regression exposes a production gap.

## Execution Progress

| Time | Step | Evidence |
|---|---|---|
| 2026-05-13 02:10:00 CEST | Added exact row-owned regression | `go-mknoon/node/pubsub_decryption_failure_test.go::TestGP023ReceivePathContinuesAfterMalformedPayload` publishes malformed decrypted group-message plaintext, observes `group:payload_parse_failed`, proves no malformed receive/plaintext side effect, then publishes a valid message over the same subscription and observes `group_message:received`. |
| 2026-05-13 02:10:00 CEST | Production assessment | No production code change was required; `handleGroupSubscription` already continues after `ParseGroupPayload` failure by emitting the diagnostic and continuing the receive loop. |

## Gate Evidence

| Gate | Result |
|---|---|
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP023')` | Passed: `ok github.com/mknoon/go-mknoon/node 2.159s`. |
| `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP023|GK029|PayloadParseFailed|MalformedPayload|HandleGroupSubscription')` | Passed: `ok github.com/mknoon/go-mknoon/node 26.459s`. |
| `gofmt` / `git diff --check` | Passed. |

## Closure Bar

- Source row GP-023 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 118, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-023 ownership and does not mask a repo-owned blocker.

## Final Verdict

Verdict: accepted/closed.

GP-023 is covered by exact tests-only Go node evidence. The row-owned behavior is the live Go receive loop's handling of malformed decrypted payloads and subsequent valid messages on the same subscription; no Dart/Flutter repository, UI, retry, durable inbox, or production Go code needed to change.
